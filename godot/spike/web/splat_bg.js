/**
 * docs/33: 3DGS under Godot canvas via Spark.
 *
 * HARD LESSON: Godot WebGL + Spark WebGL on the same page floods
 * glDrawElementsInstanced errors → main-thread starve → mouse/HUD dead.
 * Mitigations: never boot before chessroom.gd calls MW_SPLAT_START;
 * low FPS; resetState; stop immediately on GL error and restore shell.
 */
import * as THREE from "three";

const params = new URLSearchParams(location.search);
const DEBUG_TRI = params.get("splatDebug") === "1";
const splatName = (params.get("splat") || "").trim();
const DEV_ON = params.get("splatOn") === "1";

let started = false;
let stopped = false;
/** @type {THREE.WebGLRenderer | null} */
let liveRenderer = null;
window.MW_SPLAT_ACTIVE = 0;

/** Query float; missing/empty → default (Number(null)===0 must not win). */
function fitNum(k, d) {
	const raw = params.get(k);
	if (raw == null || raw === "") return d;
	const v = Number(raw);
	return Number.isFinite(v) ? v : d;
}

/**
 * lab3 / InteriorGS (igs*) are Z-up → Three Y-up (−90° X).
 * @param {import('three').Object3D} mesh
 * @param {string} name
 */
function applySplatOrientation(mesh, name) {
	if (/lab3|igs\d/i.test(name)) {
		mesh.quaternion.setFromAxisAngle(new THREE.Vector3(1, 0, 0), -Math.PI / 2);
		return;
	}
	mesh.quaternion.set(0, 0, 0, 1);
}

/**
 * Read bounding box from Spark mesh or three fallback.
 * @param {import('three').Object3D} mesh
 * @returns {import('three').Box3}
 */
function meshBBox(mesh) {
	try {
		const b = mesh.getBoundingBox?.(true);
		if (b && !b.isEmpty()) return b.clone();
	} catch {
		/* fall through */
	}
	return new THREE.Box3().setFromObject(mesh);
}

/**
 * Scale + orient, then floor-snap to Godot y=0 (chessroom pad).
 * splatYLift on URL is ignored when floor-snap is on (default) — large lifts
 * push the scan out of view → black void after shell hide.
 * @param {import('three').Object3D} mesh
 * @param {string} name
 */
function applySplatFit(mesh, name) {
	applySplatOrientation(mesh, name);
	mesh.position.set(0, 0, 0);
	mesh.scale.setScalar(1);
	mesh.updateMatrixWorld(true);
	const size0 = meshBBox(mesh).getSize(new THREE.Vector3());
	const horiz0 = Math.max(size0.x, size0.z, 1e-3);
	let s = fitNum("splatScale", NaN);
	if (!Number.isFinite(s) || s <= 0) {
		// InteriorGS rooms are already metric; don't force ~10m horizontal fit.
		if (/igs\d/i.test(name) && horiz0 >= 3) {
			s = 1;
		} else {
			s = horiz0 < 20 ? 10 / horiz0 : 1;
		}
	}
	mesh.scale.setScalar(s);
	mesh.updateMatrixWorld(true);

	const floorSnap = params.get("splatFloor") !== "0";
	if (floorSnap) {
		const lb = meshBBox(mesh);
		const c = lb.getCenter(new THREE.Vector3());
		mesh.position.set(-c.x, -lb.min.y, -c.z);
		if (params.get("splatYLift") != null && params.get("splatYLift") !== "") {
			console.warn(
				"[MW] splat_bg: splatYLift ignored (floor-snap on). Fine-tune with splatY=±0.3"
			);
		}
		mesh.position.x += fitNum("splatOx", 0);
		mesh.position.y += fitNum("splatY", 0);
		mesh.position.z += fitNum("splatOz", 0) + fitNum("splatOzNudge", 0);
	} else {
		mesh.position.set(fitNum("splatOx", 0), fitNum("splatY", 0), fitNum("splatOz", 0));
		if (/lab3/i.test(name)) {
			mesh.position.y += fitNum("splatYLift", -0.85);
			mesh.position.z += fitNum("splatOzNudge", 0.08);
		}
	}
	mesh.updateMatrixWorld(true);
	const out = meshBBox(mesh);
	console.log(
		"[MW] splat_bg fit",
		name,
		"scale=" + s.toFixed(3),
		"pos=",
		mesh.position.toArray().map((v) => +v.toFixed(2)).join(","),
		"floorSnap=" + floorSnap,
		"bboxY=",
		out.min.y.toFixed(2) + ".." + out.max.y.toFixed(2)
	);
}

/**
 * True when Godot's WebGL context has an alpha channel (underlay can show).
 * @returns {boolean}
 */
function probeGodotAlpha() {
	const c = document.getElementById("canvas");
	if (!c) {
		window.MW_SPLAT_COMPOSITE_OK = "0";
		return false;
	}
	const gl = c.getContext("webgl2") || c.getContext("webgl");
	const attrs = gl && gl.getContextAttributes ? gl.getContextAttributes() : null;
	const ok = !!(attrs && attrs.alpha);
	window.MW_SPLAT_COMPOSITE_OK = ok ? "1" : "0";
	console.log("[MW] splat_bg godot canvas alpha=", ok, attrs || {});
	return ok;
}

/**
 * Show splat above Godot (semi-transparent) when compositing is impossible.
 */
function enablePeek() {
	const el = document.getElementById("mw-splat");
	if (!el) return;
	el.style.zIndex = "2";
	el.style.opacity = "0.55";
	document.body.classList.add("mw-splat-peek");
	console.warn("[MW] splat_bg PEEK on — composite unavailable or ?splatPeek=1");
}

window.MW_SPLAT_PEEK = enablePeek;

function softenGodotClear() {
	document.body.classList.add("mw-splat-live");
	const c = document.getElementById("canvas");
	if (c) c.style.background = "transparent";
}

function clearGodotSoftening() {
	document.body.classList.remove("mw-splat-live");
	const c = document.getElementById("canvas");
	if (c) c.style.background = "";
}

/**
 * Tear down Spark and tell Godot to restore the procedural shell.
 * @param {string} reason
 */
function failSoft(reason) {
	if (stopped) return;
	stopped = true;
	window.MW_SPLAT_ACTIVE = 0;
	console.warn("[MW] splat_bg STOP:", reason);
	try {
		if (liveRenderer) {
			liveRenderer.setAnimationLoop(null);
			liveRenderer.dispose();
		}
	} catch {
		/* ignore */
	}
	liveRenderer = null;
	const el = document.getElementById("mw-splat");
	if (el) el.remove();
	clearGodotSoftening();
	try {
		window.dispatchEvent(new CustomEvent("mw-splat-fail", { detail: reason }));
	} catch {
		/* ignore */
	}
	// Godot polls this.
	window.MW_SPLAT_FAILED = reason || "gl";
}

/**
 * Start Spark under-canvas. Only from chessroom.gd (not URL deep-link).
 * @returns {Promise<void>}
 */
async function startSplat() {
	if (started || stopped) return;
	if (!DEV_ON || splatName === "") {
		console.log("[MW] splat_bg start skipped (need ?splat=&splatOn=1)");
		return;
	}
	if (!/^[a-z0-9_]+$/i.test(splatName)) {
		console.warn("[MW] splat_bg: bad splat name", splatName);
		return;
	}
	// Godot must already own the page — refuse if engine not up yet.
	if (!document.getElementById("canvas") || !window.MW_CAM_POSE) {
		console.log("[MW] splat_bg defer: waiting for Godot pose…");
		setTimeout(() => {
			started = false;
			window.MW_SPLAT_START();
		}, 500);
		return;
	}
	started = true;
	window.MW_SPLAT_ACTIVE = 0;
	window.MW_SPLAT_FAILED = "";
	softenGodotClear();

	const canvas = document.createElement("canvas");
	canvas.id = "mw-splat";
	canvas.style.cssText =
		"position:fixed;inset:0;width:100%;height:100%;z-index:0;pointer-events:none;";
	document.body.prepend(canvas);

	const renderer = new THREE.WebGLRenderer({
		canvas,
		antialias: false,
		alpha: true,
		powerPreference: "low-power",
	});
	liveRenderer = renderer;
	renderer.setClearColor(0x2a3544, 1); // slate — empty frustum ≠ pure black
	renderer.setPixelRatio(1);
	renderer.setSize(window.innerWidth, window.innerHeight);

	const scene = new THREE.Scene();
	const camera = new THREE.PerspectiveCamera(
		70,
		window.innerWidth / window.innerHeight,
		0.1,
		2000
	);
	camera.position.set(0, 1.6, 3);
	scene.add(camera);

	/** @type {{ activeSplats?: number } | null} */
	let spark = null;
	canvas.addEventListener("webglcontextlost", (e) => {
		e.preventDefault();
		failSoft("contextlost");
	});

	try {
		if (DEBUG_TRI) {
			const tri = new THREE.Mesh(
				new THREE.ConeGeometry(2, 4, 8),
				new THREE.MeshBasicMaterial({ color: 0xff3344 })
			);
			tri.position.set(0, 2, 0);
			scene.add(tri);
			window.MW_SPLAT_ACTIVE = 1;
			console.log("[MW] splat_bg DEBUG triangle mode");
		} else {
			const mod = await import("spark");
			spark = new mod.SparkRenderer({
				renderer,
				preUpdate: false,
				maxStdDev: Math.sqrt(5),
				enableLod: true,
				lodSplatCount: 48000,
			});
			renderer.xr.enabled = false;
			(camera.parent || scene).add(spark);
			const url = "media/splats/" + splatName + ".spz";
			console.log("[MW] splat_bg loading", url);
			const fileBytes = new Uint8Array(await (await fetch(url)).arrayBuffer());
			const mesh = new mod.SplatMesh({ fileBytes, fileName: splatName + ".spz" });
			await mesh.initialized;
			applySplatFit(mesh, splatName);
			scene.add(mesh);
			console.log("[MW] splat_bg ready", url);
			const compositeOk = probeGodotAlpha();
			if (!compositeOk || params.get("splatPeek") === "1") {
				enablePeek();
			}
		}
	} catch (e) {
		failSoft(String(e && e.message ? e.message : e));
		started = false;
		return;
	}

	window.addEventListener("resize", () => {
		if (stopped || !liveRenderer) return;
		camera.aspect = window.innerWidth / window.innerHeight;
		camera.updateProjectionMatrix();
		liveRenderer.setSize(window.innerWidth, window.innerHeight);
	});

	const posePos = new THREE.Vector3();
	const poseQuat = new THREE.Quaternion();
	let loggedPose = false;
	let lastDraw = 0;
	const minFrameMs = 200; // ≤5 fps — cut dual-WebGL contention
	const gl = renderer.getContext();

	renderer.setAnimationLoop(() => {
		if (stopped) return;
		const now = performance.now();
		if (now - lastDraw < minFrameMs) return;
		lastDraw = now;
		try {
			const p = window.MW_CAM_POSE;
			if (p && Array.isArray(p.pos) && Array.isArray(p.quat)) {
				posePos.fromArray(p.pos);
				poseQuat.fromArray(p.quat);
				camera.position.copy(posePos);
				camera.quaternion.copy(poseQuat);
				if (typeof p.fov === "number" && p.fov !== camera.fov) {
					camera.fov = p.fov;
					camera.updateProjectionMatrix();
				}
				if (!loggedPose) {
					loggedPose = true;
					console.log(
						"[MW] splat_bg cam pose",
						p.pos,
						"active=",
						spark && spark.activeSplats
					);
				}
			}
			if (typeof renderer.resetState === "function") {
				renderer.resetState();
			}
			renderer.render(scene, camera);
			if (spark && typeof spark.activeSplats === "number") {
				window.MW_SPLAT_ACTIVE = spark.activeSplats;
			}
			// Drain GL errors; any INVALID_OPERATION → bail (protect Godot input).
			if (gl) {
				let err = gl.getError();
				let n = 0;
				while (err !== gl.NO_ERROR && n < 8) {
					n++;
					err = gl.getError();
				}
				if (n > 0) {
					failSoft("webgl_errors=" + n);
				}
			}
		} catch (e) {
			failSoft(String(e && e.message ? e.message : e));
		}
	});
}

window.MW_SPLAT_START = () => {
	if (stopped) {
		console.log("[MW] splat_bg already failed this session; skip");
		return;
	}
	return startSplat().catch((err) => {
		console.warn("[MW] splat_bg failed:", err);
		started = false;
		failSoft(String(err && err.message ? err.message : err));
	});
};

window.MW_SPLAT_STOP = () => failSoft("manual");

// Never auto-start from ?room=chess — that raced Godot boot and killed input.
if (splatName !== "" && DEV_ON) {
	console.log(
		"[MW] splat_bg armed (only chessroom MW_SPLAT_START; no deep-link boot)"
	);
}

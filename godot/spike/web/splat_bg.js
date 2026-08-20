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
 * InteriorGS occupancy (arm parity): pin entry/ground, not geometric bbox alone.
 * @typedef {{ center: [number, number, number], groundZ: number }} IgsOcc
 */

/** Embedded fallback if .occupancy.json missing. */
const IGS_OCC_FALLBACK = {
	igs0047: {
		center: [1.5693899655600703, -3.0245500480120038, 0.0],
		groundZ: 0.0,
	},
};

/**
 * Load occupancy for igs* skins (same-origin json, then embed).
 * @param {string} name
 * @returns {Promise<IgsOcc | null>}
 */
async function loadIgsOccupancy(name) {
	if (!/igs\d/i.test(name)) return null;
	try {
		const res = await fetch("media/splats/" + name + ".occupancy.json", {
			cache: "force-cache",
		});
		if (res.ok) {
			const j = await res.json();
			const c = j?.center;
			if (Array.isArray(c) && c.length >= 2) {
				return {
					center: [Number(c[0]) || 0, Number(c[1]) || 0, Number(c[2]) || 0],
					groundZ: Number.isFinite(Number(j.groundZ))
						? Number(j.groundZ)
						: Number.isFinite(Number(c[2]))
							? Number(c[2])
							: 0,
				};
			}
		}
	} catch {
		/* fall through */
	}
	const fb = IGS_OCC_FALLBACK[name];
	return fb
		? { center: /** @type {[number,number,number]} */ (fb.center.slice()), groundZ: fb.groundZ }
		: null;
}

/**
 * Scale + orient. InteriorGS: occupancy entry/ground (mine-world-arm fitArmWorkcell).
 * lab3: geometric floor-snap.
 * @param {import('three').Object3D} mesh
 * @param {string} name
 * @param {IgsOcc | null} [igsOcc]
 */
function applySplatFit(mesh, name, igsOcc = null) {
	applySplatOrientation(mesh, name);
	mesh.position.set(0, 0, 0);
	mesh.scale.setScalar(1);
	mesh.updateMatrixWorld(true);
	const size0 = meshBBox(mesh).getSize(new THREE.Vector3());
	const horiz0 = Math.max(size0.x, size0.z, 1e-3);
	const isIgs = /igs\d/i.test(name);
	let s = fitNum("splatScale", NaN);
	if (!Number.isFinite(s) || s <= 0) {
		// arm: igs scale 1 unless huge (>40m → shrink to ~28m)
		if (isIgs) {
			s = horiz0 > 40 ? 28 / horiz0 : 1;
		} else {
			s = horiz0 < 20 ? 10 / horiz0 : 1;
		}
	}
	mesh.scale.setScalar(s);
	mesh.updateMatrixWorld(true);

	const ox = fitNum("splatOx", 0);
	const oz = fitNum("splatOz", 0);
	const yNudge = fitNum("splatY", 0);

	if (isIgs && igsOcc && Array.isArray(igsOcc.center)) {
		// Chessroom pad ≈ origin; arm desk uses splatShift=2.2 — default 0 here.
		const fwdM = fitNum("splatShift", 0);
		const [cx, cy, cz] = igsOcc.center;
		const groundZ = Number.isFinite(igsOcc.groundZ) ? igsOcc.groundZ : 0;
		mesh.updateMatrixWorld(true);
		const entry = new THREE.Vector3(cx, cy, cz).applyMatrix4(mesh.matrixWorld);
		const ground = new THREE.Vector3(cx, cy, groundZ).applyMatrix4(mesh.matrixWorld);
		mesh.position.x += 0 - entry.x + ox;
		mesh.position.z += -fwdM - entry.z + oz;
		mesh.position.y += 0 - ground.y + yNudge;
		mesh.updateMatrixWorld(true);
		const ground2 = new THREE.Vector3(cx, cy, groundZ).applyMatrix4(mesh.matrixWorld);
		mesh.position.y += 0 - ground2.y;
		mesh.updateMatrixWorld(true);
		const out = meshBBox(mesh);
		console.log(
			"[MW] splat_bg fit",
			name,
			"igs-occupancy",
			"scale=" + s.toFixed(3),
			"pos=",
			mesh.position.toArray().map((v) => +v.toFixed(2)).join(","),
			"entryLocal=",
			[cx, cy, cz].map((v) => +v.toFixed(2)).join(","),
			"fwd=" + fwdM.toFixed(2),
			"bboxY=",
			out.min.y.toFixed(2) + ".." + out.max.y.toFixed(2)
		);
		return;
	}

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
		mesh.position.x += ox;
		mesh.position.y += yNudge;
		mesh.position.z += oz + fitNum("splatOzNudge", 0);
	} else {
		mesh.position.set(ox, yNudge, oz);
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
			const igsOcc = await loadIgsOccupancy(splatName);
			applySplatFit(mesh, splatName, igsOcc);
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
	// Splat-P1d (docs/35 §2): adaptive frame pacing — 5fps idle, ~30fps while
	// MW_CAM_POSE moves; decay back after holdMs of stillness.
	const MIN_FRAME_IDLE_MS = 200;
	const MIN_FRAME_ACTIVE_MS = 33;
	const BOOST_HOLD_MS = 400;
	const MOVE_EPS_SQ = 0.002 * 0.002;
	const ROT_EPS_DOT = 1 - 0.0005;
	let minFrameMs = MIN_FRAME_IDLE_MS;
	let boostUntil = 0;
	let lastPosePos = null;
	let lastPoseQuat = null;
	const gl = renderer.getContext();

	renderer.setAnimationLoop(() => {
		if (stopped) return;
		const now = performance.now();
		const p0 = window.MW_CAM_POSE;
		if (p0 && Array.isArray(p0.pos) && Array.isArray(p0.quat)) {
			let moved = lastPosePos === null;
			if (!moved) {
				const dx = p0.pos[0] - lastPosePos[0];
				const dy = p0.pos[1] - lastPosePos[1];
				const dz = p0.pos[2] - lastPosePos[2];
				const dot =
					p0.quat[0] * lastPoseQuat[0] +
					p0.quat[1] * lastPoseQuat[1] +
					p0.quat[2] * lastPoseQuat[2] +
					p0.quat[3] * lastPoseQuat[3];
				moved =
					dx * dx + dy * dy + dz * dz > MOVE_EPS_SQ ||
					Math.abs(dot) < ROT_EPS_DOT;
			}
			if (moved) boostUntil = now + BOOST_HOLD_MS;
			lastPosePos = p0.pos;
			lastPoseQuat = p0.quat;
		}
		minFrameMs = now < boostUntil ? MIN_FRAME_ACTIVE_MS : MIN_FRAME_IDLE_MS;
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

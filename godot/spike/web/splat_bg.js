/**
 * P1 (docs/33): 3DGS backdrop via Spark on a canvas UNDER the Godot canvas.
 * Opt-in only: ?splat=<name> + ?level=demo_race (PoC scope).
 * Asset: media/splats/<name>.spz (same-origin, ≤25MB per docs/33 §4).
 * Camera: reads window.MW_CAM_POSE {pos:[x,y,z], quat:[x,y,z,w], fov} pushed
 * by mw/splat_bridge.gd; static overview fallback until the bridge lands.
 * Visual only — never touches input / physics (docs/29 red line respected).
 */
import * as THREE from "three";

const params = new URLSearchParams(location.search);
/** Debug: ?splatDebug=1 renders a red test triangle instead of the splat. */
const DEBUG_TRI = params.get("splatDebug") === "1";
const splatName = (params.get("splat") || "").trim();
const level = (params.get("level") || "").trim();

/** Hub (no level param = demo_hub) or race PoC, only when explicitly requested. */
if (splatName !== "" && (level === "" || level === "demo_hub" || level === "demo_race")) {
	boot().catch((err) => console.warn("[MW] splat_bg failed:", err));
}

async function boot() {
	if (!/^[a-z0-9_]+$/i.test(splatName)) {
		console.warn("[MW] splat_bg: bad splat name", splatName);
		return;
	}
	// Under-canvas: fixed, below Godot #canvas, never receives events.
	const canvas = document.createElement("canvas");
	canvas.id = "mw-splat";
	canvas.style.cssText =
		"position:fixed;inset:0;width:100%;height:100%;z-index:0;pointer-events:none;";
	document.body.prepend(canvas);
	// Godot canvas must let the splat show through (viewport.transparent_bg
	// is set by splat_bridge.gd on the engine side).
	const godotCanvas = document.getElementById("canvas");
	if (godotCanvas) {
		godotCanvas.style.position = "relative";
		godotCanvas.style.zIndex = "1";
		godotCanvas.style.background = "transparent";
	}

	const renderer = new THREE.WebGLRenderer({
		canvas,
		antialias: false, // E8: Spark breaks with MSAA.
		alpha: true,
	});
	renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
	renderer.setSize(window.innerWidth, window.innerHeight);

	const scene = new THREE.Scene();
	const camera = new THREE.PerspectiveCamera(
		70,
		window.innerWidth / window.innerHeight,
		0.1,
		2000
	);
	// Fallback overview until MW_CAM_POSE arrives.
	camera.position.set(0, 30, 40);
	camera.lookAt(0, 0, 0);
	scene.add(camera);

	if (DEBUG_TRI) {
		const tri = new THREE.Mesh(
			new THREE.ConeGeometry(2, 4, 8),
			new THREE.MeshBasicMaterial({ color: 0xff3344 })
		);
		tri.position.set(0, 2, 0);
		scene.add(tri);
		console.log("[MW] splat_bg DEBUG triangle mode");
	} else {
		const { SparkRenderer, SplatMesh } = await import("spark");
		const spark = new SparkRenderer({ renderer, preUpdate: false });
		scene.add(spark);
		const url = "media/splats/" + splatName + ".spz";
		console.log("[MW] splat_bg loading", url);
		const mesh = new SplatMesh({ url });
		await mesh.initialized;
		// E5: horizontal fit only (never yaw — Z-up→Y-up then rotateY tips the room).
		const fitNum = (k, d) => {
			const v = Number(params.get(k));
			return Number.isFinite(v) ? v : d;
		};
		mesh.position.set(fitNum("splatOx", 0), fitNum("splatY", 0), fitNum("splatOz", 0));
		const s = fitNum("splatScale", 1);
		if (s !== 1) mesh.scale.setScalar(s);
		scene.add(mesh);
		console.log("[MW] splat_bg ready", url);
	}

	window.addEventListener("resize", () => {
		camera.aspect = window.innerWidth / window.innerHeight;
		camera.updateProjectionMatrix();
		renderer.setSize(window.innerWidth, window.innerHeight);
	});

	const posePos = new THREE.Vector3();
	const poseQuat = new THREE.Quaternion();
	renderer.setAnimationLoop(() => {
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
		}
		renderer.render(scene, camera);
	});
}

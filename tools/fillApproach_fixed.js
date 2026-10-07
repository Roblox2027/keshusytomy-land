function fillApproach(api, out, ax, az, zone, width, P, seedBase, tag, stop) {
	const { decor } = api;
	const dx = zone.x - ax;
	const dz = zone.z - az;
	const len = Math.sqrt(dx * dx + dz * dz);
	if (len < 1) return;

	const ux = dx / len;
	const uz = dz / len;
	const runLen = Math.max(11, len * stop);
	const steps = Math.max(1, Math.round(runLen / 11));
	const segLen = runLen / steps;
	const yaw = yawTo(ux, uz);
	const w = Math.max(width, MIN_ROUTE_OPENING);

	for (let i = 0; i < steps; i++) {
		const t = (i + 0.5) / steps;
		out.push(decor("Approach_" + zone.id + "_" + tag + "_" + i, {
			position: [ax + ux * runLen * t, zone.y - 0.9, az + uz * runLen * t],
			size: [segLen * 1.6, 0.2, w],
			material: P.floorMaterial,
			color: P.groundAlt,
			orientation: [0, yaw, 0],
		}));
		void seedBase;
	}
}
# 日食图标生成记录

使用内置 imagegen 工具。图一是现有黑白日食图标；图二是备份原版 Celechron 图标，参考其渐变与从圆心向右的指针线。生成原图保存于 `source/eclipse-imagegen.png`，应用使用缩放后的 `eclipse.png`。

## 完整提示词

Use case: logo-brand / precise-object-edit.
Asset type: final Android app launcher icon for ChronoPilot Go, a minimalist student timetable and planning app.
Input images: Image 1 is the EDIT TARGET and defines the exact black-and-white eclipse composition on a neutral gray background. Image 2 is the ORIGINAL CELECHRON STYLE REFERENCE ONLY, specifically its gentle smooth gradients and single horizontal clock-hand-like line with a small white origin dot.
Modify Image 1 by adding ONLY these requested refinements:
1. Keep its centered circular eclipse, bright white crescent on the LEFT, predominantly black moon surface on the RIGHT, and neutral medium-gray background. Preserve the silhouette, scale, generous safety margins, proportions, and monochrome identity.
2. Introduce an elegant, soft tonal gradient at the transition from the white crescent toward the dark lunar face, inspired by Image 2's subtle gradients. The white crescent should stay luminous; the right lunar face should remain deeply black. A restrained silver-gray transition should soften the boundary without turning the moon into an all-gray globe.
3. Add exactly one thin, horizontal, round-ended line starting at the geometric center of the moon and extending rightward almost to its outer edge, with a tiny crisp white circular origin dot at the center. Match the clean straight geometry of Image 2's line. Use a subdued light-silver line that remains visible on the black face; keep it elegant and recognizable at small icon sizes.
Style: refined flat graphic with smooth controlled gradients, clean antialiased circular outlines, minimal vector-like precision. No photorealistic moon texture, no craters, no stars, no extra orbit rings, no bloom, no lens flare, no 3D bevel, no text, no watermark.
Output: ONE square 1024x1024 production-ready icon, opaque neutral gray background extending all the way to every image edge; do not add a device mockup, label, frame, drop shadow, or rounded-square outer border. Keep the full circular symbol within the central 62% of the canvas so Android adaptive-icon cropping is safe.

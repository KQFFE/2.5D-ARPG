shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// depth_draw_always matters. Without it a transparent material never writes depth, so
// the cottage's own parts (wall, roof, window, chimney) are resolved purely by
// transparent draw order - and that order flips at grazing angles, which is exactly
// what happens at the screen edges. Windows and chimneys then popped in and out as
// they were drawn behind the wall they sit on. Writing depth hands the decision to the
// depth buffer instead, which is stable from every angle and costs nothing extra.
// It is safe here because the player and the ground are opaque and therefore already
// drawn before this transparent pass, so a faded wall still lets the player show through.

// Per-structure occluder fade for the village buildings.
//
// This material replaces the structures' original StandardMaterial3D (cottage walls /
// roof / beams / windows / stone, gate beam / iron). One ShaderMaterial instance is
// owned by each registered structure, so the per-structure gate below never leaks
// from one building to another.
//
// The reveal is a SCREEN-SPACE circle centred on the player's projected feet. That is
// what makes it work for a house 7-8 m in front of the camera: a world-space sphere
// small enough not to swallow the whole building can never reach it.
//
// Two independent conditions must both hold before a fragment goes see-through:
//   1. fade_active == 1 - the script proved the player is genuinely BEHIND this
//      structure (further from the camera along the view direction than the
//      structure's far footprint edge). Standing beside a house leaves it at 0, so
//      the wall facing the camera stays fully opaque.
//   2. the fragment is inside the screen-space circle around the player's feet AND
//      nearer the camera than the player (fade_depth_margin), so the reveal stays a
//      disc on the silhouette the player is actually hidden behind, not the whole
//      building and not the ground under the player's own feet.
//
// Per fragment: 2 lengths + 1 smoothstep + 1 step + 1 mix. No scene traversal, no
// raycast, no per-frame cost that grows with the number of structures.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_energy = 0.0;

// Gate written by res://scripts/occluder_fader.gd. 1.0 only while the player is
// behind THIS structure. 0.0 keeps the structure solid.
uniform float fade_active : hint_range(0.0, 1.0) = 0.0;

// Screen-space circle around the player's projected feet. UV space (0..1).
uniform vec2 fade_screen_center = vec2(0.5, 0.5);
uniform float fade_screen_radius = 0.18;
uniform float fade_screen_aspect = 1.777;

// How opaque a fully revealed fragment becomes (0 = invisible, 1 = solid).
uniform float fade_min_alpha : hint_range(0.0, 1.0) = 0.25;
// Soft edge of the reveal circle, as a fraction of fade_screen_radius.
uniform float fade_softness : hint_range(0.0, 1.0) = 0.35;
// How much nearer the camera than the player a fragment must be to count as
// standing between the camera and the player.
uniform float fade_depth_margin = 0.5;

// Player's feet position in world space, used only for the depth (front) test.
uniform vec3 fade_center = vec3(0.0);

void fragment() {
    // Screen-space circle: x is scaled by the aspect ratio so the reveal is round
    // and not an ellipse on a non-square viewport.
    vec2 d = (SCREEN_UV - fade_screen_center) * vec2(fade_screen_aspect, 1.0);
    float t = smoothstep(fade_screen_radius * (1.0 - fade_softness), fade_screen_radius, length(d));

    // Front test: is this fragment between the camera and the player?
    float to_player = distance(CAMERA_POSITION_WORLD, fade_center);
    float to_frag = distance(CAMERA_POSITION_WORLD, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
    float in_front = step(to_frag + fade_depth_margin, to_player);

    float reveal = fade_active * (1.0 - t) * in_front;

    ALBEDO = albedo.rgb;
    ROUGHNESS = roughness;
    METALLIC = metallic;
    EMISSION = emission_color.rgb * emission_energy;
    ALPHA = mix(1.0, fade_min_alpha, reveal);
}

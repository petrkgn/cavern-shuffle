components {
  id: "one_shot_effect"
  component: "/game/scripts/one_shot_effect.script"
}
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "default_animation: \"slash_anim\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "blend_mode: BLEND_MODE_ADD\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/assets/effects/slash.atlas\"\n"
  "}\n"
  ""
}

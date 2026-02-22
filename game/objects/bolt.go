components {
  id: "bolt_controller"
  component: "/game/scripts/bolt_controller.script"
}
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "default_animation: \"bolt\"\n"
  "material: \"/builtins/materials/sprite.material\"\n"
  "blend_mode: BLEND_MODE_ADD\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/assets/lightning/lightning.atlas\"\n"
  "}\n"
  ""
  position {
    z: -0.9
  }
  scale {
    x: 0.4
    y: 0.4
  }
}

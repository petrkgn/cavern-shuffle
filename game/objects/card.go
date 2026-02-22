components {
  id: "card"
  component: "/game/scripts/card.script"
}
embedded_components {
  id: "sprite"
  type: "sprite"
  data: "default_animation: \"card_back\"\n"
  "material: \"/game/shaders/card.material\"\n"
  "textures {\n"
  "  sampler: \"texture_sampler\"\n"
  "  texture: \"/assets/cards/kcards.atlas\"\n"
  "}\n"
  ""
}

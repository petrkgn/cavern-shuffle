varying mediump vec2 var_texcoord0;
varying mediump vec2 var_screen_uv;

uniform lowp sampler2D texture_sampler;
uniform lowp vec4 flash_params;
uniform lowp vec4 time;
uniform lowp vec4 resolution; // [НОВОЕ] Нужно добавить в material!

// Шум (Без изменений)
float rand(vec2 p){
	p+=vec2(.2127, .3713)+p.x+p.y;
	vec2 r=4.789*sin(789.123*(p));
	return fract(r.x*r.y);
}
float sn(vec2 p){
	vec2 i=floor(p-.5);
	vec2 f=fract(p-.5);
	f = f*f*f*(f*(f*6.0-15.0)+10.0);
	float rt=mix(rand(i),rand(i+vec2(1.,0.)),f.x);
	float rb=mix(rand(i+vec2(0.,1.)),rand(i+vec2(1.,1.)),f.x);
	return mix(rt,rb,f.y);
}

void main()
{
	vec4 castle_texture = texture2D(texture_sampler, var_texcoord0);
	if (castle_texture.a < 0.1) discard;

	// [НОВОЕ] Считаем Aspect Ratio
	float aspect = resolution.x / resolution.y;

	// --- ТЕНИ ---
	// [ИСПРАВЛЕНО] Умножаем X на aspect, чтобы тени совпадали с формой облаков на небе
	vec2 p = var_screen_uv.xy * vec2(3.0 * aspect, 4.3);
	p.x -= time.x * 0.2;
	p.y *= 1.3;
	float newT = time.x * 0.4 + sn(vec2(time.x * 1.0)) * 0.1;

	float cloud_noise = 0.5 * sn(p) + 0.25 * sn(2.04*p + newT*1.1) - 0.125 * sn(4.03*p - time.x*0.3) + 0.0625 * sn(8.02*p - time.x*0.4);
	cloud_noise = clamp(cloud_noise, 0.0, 1.0);

	const float SHADOW_INTENSITY = 1.0;
	float shadow_factor = mix(1.0 - SHADOW_INTENSITY, 1.0, cloud_noise);

	// --- ГЛАЗА (Без изменений) ---
	float redness = castle_texture.r - max(castle_texture.g, castle_texture.b);
	float eye_mask = smoothstep(0.1, 0.4, redness);
	float darkness = 0.7 - shadow_factor;
	vec3 wall_color = castle_texture.rgb * shadow_factor;
	vec3 eye_color = castle_texture.rgb * (darkness * 3.0); 
	vec3 castle_color_with_shadows = mix(wall_color, eye_color, eye_mask);

	// --- ВСПЫШКА (ФИЗИЧЕСКИ КОРРЕКТНАЯ) ---
	vec2 flash_origin_uv = flash_params.xy;
	float flash_intensity = flash_params.z;

	// Вектор от пикселя замка до центра вспышки
	vec2 diff = var_screen_uv - flash_origin_uv;
	diff.x *= aspect; // Коррекция для круглого пятна

	// Убираем искусственное сжатие по Y (diff.y *= 0.4), 
	// чтобы свет падал естественно и доставал до низа.
	// Или делаем его мягче, например 0.7, если хотите вытянутый блик.
	// Но для дальности лучше убрать или ослабить.
	diff.y *= 0.6; 

	float dist_sq = dot(diff, diff); // Дистанция в квадрате (быстрее чем length)

	// [ГЛАВНОЕ ИЗМЕНЕНИЕ] Вместо smoothstep используем "бесконечное" затухание.
	// Формула: 1.0 / (1.0 + Коэффициент * Дистанция^2)
	// Чем меньше Коэффициент, тем дальше бьет свет.
	// Попробуйте значения от 2.0 (далеко) до 10.0 (близко).
	float light_falloff = 1.0 / (1.0 + 4.0 * dist_sq);

	// Вертикальный градиент (чтобы подсвечивало сверху)
	// Расширяем диапазон (от -0.2), чтобы свет доставал до самого низа замка
	float vertical_gradient = smoothstep(-0.2, 0.8, var_screen_uv.y);

	float final_flash = light_falloff * vertical_gradient;

	// Применяем интенсивность
	float lightning_flash = final_flash * flash_intensity;

	// Финал (смешивание)
	vec3 lightning_color = vec3(1.0, 1.0, 1.2);
	// Увеличил множитель (* 1.2), так как физическое затухание мягче, чем smoothstep
	vec3 lit_castle_color = castle_color_with_shadows + (lightning_color * lightning_flash * 1.2);

	const float BACKLIGHT_INTENSITY = 0.03;
	vec3 final_color = lit_castle_color + BACKLIGHT_INTENSITY;

	gl_FragColor = vec4(final_color, castle_texture.a);
}
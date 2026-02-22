varying mediump vec2 var_texcoord0;

uniform lowp vec4 time;
uniform lowp vec4 resolution;
uniform lowp vec4 flash_params; // xy = origin (0..1), z = intensity

// Константы
const float PI = 3.14159265359;

// ==========================================================
//      ФУНКЦИИ ШУМА (Без изменений)
// ==========================================================
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

void mainImage(out vec4 fragColor, in vec2 uv) {
	// [ИСПРАВЛЕНО] Мы больше не пересчитываем UV через resolution.y.
	// Мы получаем готовые UV (0..1) из main().

	// Aspect Ratio (Соотношение сторон) для коррекции кругов
	float aspect = resolution.x / resolution.y;

	// --- Облака ---
	// [КОРРЕКЦИЯ] Умножаем p.x на aspect, чтобы облака не растягивались на широком экране
	vec2 p = uv.xy * vec2(3.0 * aspect, 4.3);

	float f = 0.5 * sn(p) + 0.25 * sn(2.0 * p) + 0.125 * sn(4.0 * p) + 0.0625 * sn(8.0 * p) + 0.03125 * sn(16.0 * p) + 0.015 * sn(32.0 * p);
	p.x -= time.x * 0.2;
	p.y *= 1.3;
	float newT = time.x * 0.4 + sn(vec2(time.x * 1.0)) * 0.1;
	float f2 = 0.5 * sn(p) + 0.25 * sn(2.04 * p + newT * 1.1) - 0.125 * sn(4.03 * p - time.x * 0.3) + 0.0625 * sn(8.02 * p - time.x * 0.4) + 0.03125 * sn(16.01 * p + time.x * 0.5) + 0.018 * sn(24.02 * p);
	float f4 = f2 * smoothstep(0.0, 1.0, uv.y);

	const float cloud_opacity_multiplier = 2.5;
	float cloud_mix_factor = f4 * f * cloud_opacity_multiplier;

	vec3 clouds = mix(vec3(-0.4, -0.4, -0.15), vec3(1.4, 1.4, 1.3), cloud_mix_factor);

	// --- Луна (ИСПРАВЛЕНО ДЛЯ ЛЮБЫХ ЭКРАНОВ) ---

	// 1. Приводим UV к "квадратным" координатам, где Y = 0..1, а X пропорционален экрану
	vec2 uv_square = uv;
	uv_square.x *= aspect;

	// 2. Позиция луны (0.2, 0.9) тоже должна быть адаптирована под этот масштаб
	vec2 moonp = vec2(0.2, 0.9);
	moonp.x *= aspect; 

	// Теперь считаем честную дистанцию между двумя точками в квадратном пространстве
	float moon_dist = 1.0 - distance(uv_square, moonp);

	float moon = smoothstep(0.95, 0.956, moon_dist);

	// Кратер (смещаем относительно новой позиции луны)
	vec2 moonp2 = moonp + vec2(0.015, 0.0);
	float moon_dist2 = 1.0 - distance(uv_square, moonp2);

	moon -= smoothstep(0.93, 0.956, moon_dist2);
	moon = clamp(moon, 0.0, 1.0);

	// Свечение (Glow) используем ту же скорректированную дистанцию
	float moon_glow = 1.0 - distance(uv_square, moonp);
	moon += 0.3 * smoothstep(0.80, 0.956, moon_glow);

	// Свечение облаков вокруг луны
	float moon_glow_falloff = 1.0 - smoothstep(0.0, 0.99, distance(uv_square, moonp));
	float glow_intensity = moon_glow_falloff * sqrt(moon_glow_falloff);
	clouds += glow_intensity * 0.3;
	
	// --- Вспышка (ИСПРАВЛЕНО) ---
	float lightning_flash = 0.0;
	vec3 lightning_color = vec3(1.0, 1.0, 1.1); // Чуть голубоватый

	vec2 flash_origin_uv = flash_params.xy; // Это координаты 0..1, пришедшие из скрипта
	float flash_intensity = flash_params.z;

	if (flash_intensity > 0.0) {
		// [ВАЖНО] Считаем дистанцию с учетом Aspect Ratio.
		// Иначе на широком экране вспышка будет овальной, а координаты "съедут".
		vec2 d = (uv - flash_origin_uv);
		d.x *= aspect;

		float flash_dist = length(d);

		// Вспышка (Glow)
		float flash = 1.0 - smoothstep(0.0, 1.2, flash_dist); // Радиус ~1.2 по высоте экрана
		lightning_flash = pow(flash, 2.0) * flash_intensity;
	}

	// Собираем цвета
	vec3 final_color_rgb = clouds + vec3(moon) + (lightning_color * lightning_flash * 0.8);

	// --- Финальная Альфа ---
	float cloud_density = smoothstep(0.0, 0.7, f4 * f);
	float final_alpha = max(cloud_density, moon);
	final_alpha = max(final_alpha, lightning_flash * 0.5); 
	final_alpha = clamp(final_alpha, 0.0, 1.0);

	fragColor = vec4(final_color_rgb, final_alpha);
}

void main() {
	// [ИЗМЕНЕНО] Просто передаем texcoord (0..1) дальше. Не умножаем на resolution.
	mainImage(gl_FragColor, var_texcoord0);
}
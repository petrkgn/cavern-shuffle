// atmospheric_sky.fp (Исправленная версия)
varying mediump vec2 var_texcoord0;
varying mediump vec2 var_position_local;
uniform lowp sampler2D texture_sampler;
uniform lowp vec4 time;
uniform lowp vec4 resolution;
uniform lowp vec4 screen_size;

// ==========================================================
//      === БЛОК НАСТРОЕК ТУМАНА ===
// ==========================================================
const float FOG_DENSITY = 0.7;      // Плотность тумана (0.0 - 1.0)
const float FOG_HEIGHT = 0.8;       // Высота тумана (0.0 - 1.0)
const float FOG_SPEED = 0.5;        // Скорость движения (-1.0 - 1.0, отрицательные значения - влево)
const vec3 FOG_COLOR = vec3(1.0, 0.0, 1.0); // Цвет тумана
const int FOG_POSITION = 1;         // 0 - внизу, 1 - вверху

// ==========================================================
//      === БЛОК НАСТРОЕК МОЛНИИ ===
// ==========================================================
const float LIGHTNING_THICKNESS = 40.0;
const float LIGHTNING_INTENSITY = 1.3;
const float FLASH_INTENSITY = 1.1;

// Константы для оптимизации
const float PI = 3.14159265359;

// ==========================================================
//      === БЛОК 1: ВОССТАНОВЛЕННЫЕ ФУНКЦИИ ШУМА ===
// ==========================================================

// Восстановленная оригинальная функция rand
float rand(vec2 p){
	p+=vec2(.2127, .3713)+p.x+p.y;
	vec2 r=4.789*sin(789.123*(p));
	return fract(r.x*r.y);
}

// Восстановленная оригинальная функция sn
float sn(vec2 p){
	vec2 i=floor(p-.5);
	vec2 f=fract(p-.5);
	f = f*f*f*(f*(f*6.0-15.0)+10.0);
	float rt=mix(rand(i),rand(i+vec2(1.,0.)),f.x);
	float rb=mix(rand(i+vec2(0.,1.)),rand(i+vec2(1.,1.)),f.x);
	return mix(rt,rb,f.y);
}

// Оптимизированная хэш-функция (оставляем для других частей кода)
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(15.32, 35.78))) * 43758.23);
}

// Оптимизированная хэш-функция возвращающая vec2
vec2 hash2(vec2 p) {
	return vec2(hash(p*.754),hash(1.5743*p.yx+4.5891))-.5;
}

// Оптимизированный шум возвращающий vec2
vec2 noise2(vec2 x) {
	vec2 p = floor(x);
	vec2 f = fract(x);
	f = f*f*(3.0-2.0*f);
	vec2 res = mix(mix( hash2(p), hash2(p + vec2(1.0, 0.0)),f.x),
	mix( hash2(p + vec2(0.0, 1.0)), hash2(p + vec2(1.0, 1.0)),f.x),f.y);
	return res;
}

// Оптимизированная функция расстояния до отрезка
float dseg(vec2 ba, vec2 pa) {
	float h = clamp(dot(pa, ba)/dot(ba,ba), -0.2, 1.0);
	return length(pa - ba*h);
}

// ==========================================================
//      === ФУНКЦИЯ ТУМАНА ===
// ==========================================================
vec3 applyFog(vec3 sceneColor, vec2 uv, float time) {
	// Определяем положение тумана в зависимости от настройки
	float fogPosition;
	if (FOG_POSITION == 0) {
		// Туман внизу
		fogPosition = uv.y;
	} else {
		// Туман вверху
		fogPosition = 1.0 - uv.y;
	}

	// Ограничиваем туман только выбранной частью экрана
	float fogFactor = smoothstep( FOG_HEIGHT, 1.0, fogPosition);

	// Добавляем движение тумана
	vec2 fogUV = uv;
	fogUV.x += time * FOG_SPEED * 0.1;

	// Создаем паттерн тумана с помощью шума
	float fogNoise = sn(fogUV * 2.0) * 0.5 + 0.5;
	fogNoise = mix(fogNoise, sn(fogUV * 4.0 + 10.0), 0.4);

	// Увеличиваем плотность тумана от края к центру
	fogFactor *= fogNoise * FOG_DENSITY;

	// Обеспечиваем плавное смешивание
	fogFactor = clamp(fogFactor, 0.0, 1.0);

	// Смешиваем цвет сцены с цветом тумана
	return mix(sceneColor, FOG_COLOR, fogFactor);
}

// ==========================================================
//      === БЛОК 2: МОДИФИЦИРОВАННЫЕ ФУНКЦИИ МОЛНИИ ===
// ==========================================================

// Функция ветки молнии (арки)
float arc(vec2 x, vec2 p, vec2 dir, float iTime) {
	vec2 r = p;
	float d = 10.0;

	for (int i = 0; i < 5; i++) {
		vec2 s = noise2(r + iTime) + dir;
		d = min(d, dseg(s, x - r));
		r += s;
	}
	return d * 3.0;
}

// Основная функция молнии
float thunderbolt(vec2 x, vec2 origin, float iTime) {
	vec2 r = origin;
	float d = 1000.0;
	float dist = length(origin - x);

	for (int i = 0; i < 19; i++) {
		if (r.y < -12.0) break;

		vec2 s = (noise2(r + iTime) + vec2(0.0, -0.7)) * 2.0;
		dist = dseg(s, x - r);
		d = min(d, dist);
		r += s;

		// Оптимизированное условие для веток
		if ((i % 5) == 0) {
			if ((i % 10) == 0) {
				d = min(d, arc(x, r, vec2(0.3, -0.5), iTime));
			} else {
				d = min(d, arc(x, r, vec2(-0.3, -0.5), iTime));
			}
		}
	}

	return exp(-LIGHTNING_THICKNESS * d) + 0.2 * exp(-dist);
}

// ==========================================================
//      === ГЛАВНАЯ ФУНКЦИЯ РИСОВАНИЯ ===
// ==========================================================
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
	vec2 uv = fragCoord.xy / resolution.y;

	// --- Часть 1: Рисуем фон ---
	vec2 p = uv.xy * vec2(3.0, 4.3);

	// Восстановленный оригинальный шум для облаков
	float f = 0.5 * sn(p) + 0.25 * sn(2.0 * p) + 0.125 * sn(4.0 * p) + 0.0625 * sn(8.0 * p) + 0.03125 * sn(16.0 * p) + 0.015 * sn(32.0 * p);

	p.x -= time.x * 0.2;
	p.y *= 1.3;
	float newT = time.x * 0.4 + sn(vec2(time.x * 1.0)) * 0.1;

	float f2 = 0.5 * sn(p) + 0.25 * sn(2.04 * p + newT * 1.1) - 0.125 * sn(4.03 * p - time.x * 0.3) + 0.0625 * sn(8.02 * p - time.x * 0.4) + 0.03125 * sn(16.01 * p + time.x * 0.5) + 0.018 * sn(24.02 * p);
	float f4 = f2 * smoothstep(0.0, 1.0, uv.y);

	vec3 clouds = mix(vec3(-0.4, -0.4, -0.15), vec3(1.4, 1.4, 1.3), f4 * f);

	// Звезды с использованием оригинальной функции rand
	vec3 stars = vec3(0.0);
	vec2 star_uv = uv * 200.0;
	vec2 star_grid = floor(star_uv);
	float star_val = rand(star_grid);

	if (star_val > 0.997) {
		float twinkle_speed = 0.5;
		float twinkle_sharpness = 16.0;
		float random_speed = twinkle_speed * (0.5 + star_val * 1.5);
		float random_phase = star_val * (2.0 * PI);
		float base_twinkle = 0.5 + 0.5 * sin(time.x * random_speed + random_phase);
		float sharp_twinkle = pow(base_twinkle, twinkle_sharpness);
		stars = vec3(sharp_twinkle);
	}

	// Оптимизированное рисование луны
	vec2 moonp = vec2(0.2, 0.9);
	float moon_dist = 1.0 - length(uv - moonp);
	float moon = smoothstep(0.95, 0.956, moon_dist);

	vec2 moonp2 = moonp + vec2(0.015, 0.0);
	float moon_dist2 = 1.0 - length(uv - moonp2);
	moon -= smoothstep(0.93, 0.956, moon_dist2);
	moon = clamp(moon, 0.0, 1.0);

	float moon_glow = 1.0 - length(uv - moonp);
	moon += 0.3 * smoothstep(0.80, 0.956, moon_glow);

	// Оптимизированное свечение луны
	float moon_glow_falloff = 1.0 - smoothstep(0.0, 0.99, distance(var_position_local, moonp));
	float glow_intensity = moon_glow_falloff * sqrt(moon_glow_falloff); // Приближение x^1.5
	clouds += glow_intensity * 0.3;

	// --- Часть 2: Синхронизированная молния и вспышка ---
	float lightning_flash = 0.0;
	float bolt_brightness = 0.0;
	vec3 lightning_color = vec3(1.0, 1.0, mix(1.2, 1.0, step(300.0, screen_size.x)));

	// Используем оригинальную hash для триггера молнии
	float t = hash(vec2(floor(5.0 * time.x)));

	// Восстанавливаем оригинальную логику с условием if
	if (hash(vec2(t + 2.3)) > 0.8) {
		vec2 flash_origin_uv = vec2(0.2 + 0.6 * hash(vec2(t)), 0.75);

		// Вспышка
		float flash_dist = distance(uv, flash_origin_uv);
		float flash = 1.0 - smoothstep(0.0, 0.9, flash_dist);
		lightning_flash = pow(flash, 2.0) * FLASH_INTENSITY;

		// Молния
		vec2 lightning_uv = 2.0 * var_position_local - 1.0;
		lightning_uv.y *= -1.0;
		vec2 lightning_origin = (flash_origin_uv * 2.0 - 1.0) * vec2(1.0, -1.0);

		lightning_origin *= 10.0;
		vec2 current_pos = lightning_uv * 10.0 + 2.0 * noise2(5.0 * lightning_uv);

		bolt_brightness = thunderbolt(current_pos, lightning_origin, time.x);
	}

	// --- Часть 3: Сборка финальной сцены ---
	vec3 lightning_bolt_effect = clamp(lightning_color * bolt_brightness * LIGHTNING_INTENSITY, 0.0, 1.0);
	vec3 background_color = clouds + vec3(moon) + stars + (lightning_color * lightning_flash * 0.6);
	background_color += lightning_bolt_effect;

	vec4 castle_texture = texture2D(texture_sampler, var_texcoord0);
	vec3 final_castle_color = castle_texture.rgb + (lightning_color * lightning_flash * 0.6 * castle_texture.a);

	vec3 final_color = mix(background_color, final_castle_color, castle_texture.a);
	vec2 fogUV = uv;

	// Применяем туман поверх всей сцены
	final_color = applyFog(final_color, fogUV, time.x);

	fragColor = vec4(final_color, 1.0);
}

//----------- КОНЕЦ КОДА -----------
void main() {
	vec2 fragCoord = var_position_local.xy * resolution.xy;
	mainImage(gl_FragColor, fragCoord);
}
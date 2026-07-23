// // assets/shaders/card_flip.fp
// varying mediump vec2 var_texcoord0;
// varying mediump float var_rot;
// 
// uniform lowp sampler2D texture_sampler;
// uniform lowp vec4 tint;
// 
// void main()
// {
// 	// Семплируем текстуру
// 	lowp vec4 color = texture2D(texture_sampler, var_texcoord0);
// 
// 	// Применяем стандартный tint (например, для прозрачности)
// 	lowp vec4 tinted_color = color * tint;
// 
// 	// Эффект "Flourish" (блик)
// 	// В PICO-8 палитра менялась при rot между -0.3 и -0.5.
// 	// Здесь мы просто добавим яркости, когда карта почти ребром.
// 	// Диапазон "вспышки": abs(rot) < 0.3
// 	float flash = 0.0;
// 	if (abs(var_rot) < 0.3) {
// 		// Чем ближе к 0, тем ярче, но не в самом 0 (там карту не видно).
// 		flash = 0.4 * (1.0 - abs(var_rot) / 0.3);
// 	}
// 
// 	// Прибавляем flash к RGB (не к Alpha!)
// 	tinted_color.rgb += vec3(flash);
// 
// 	gl_FragColor = tinted_color;
// }
// varying mediump vec2 var_texcoord0;
// varying mediump float var_rot;
// 
// uniform lowp sampler2D texture_sampler;
// uniform lowp vec4 tint;
// 
// void main()
// {
// 	lowp vec4 color = texture2D(texture_sampler, var_texcoord0);
// 
// 	if (color.a < 0.01) discard;
// 
// 	float angle = abs(var_rot); // 1.0 (плоско) -> 0.0 (ребро)
// 
// 	// === НАСТРОЙКА ДИАПАЗОНА ТЕНИ ===
// 
// 	// Было: smoothstep(0.15, 0.7, angle)
// 	// Стало: smoothstep(0.35, 0.9, angle)
// 
// 	// 0.9: Тень начинает появляться почти сразу, как карта начала наклон (еще очень широкая).
// 	// 0.35: Тень достигает максимума, когда карта еще имеет ~35% ширины (а не исчезла в нитку).
// 	// Это создает "широкое пятно" темноты в середине анимации.
// 	float shadow_intensity = 1.0 - smoothstep(0.6, 0.9, angle);
// 
// 	// === СИЛА ЗАТЕМНЕНИЯ ===
// 	// 0.85 - достаточно глубокий черный.
// 	float max_darkness = 0.6;
// 
// 	vec3 final_rgb = mix(color.rgb * tint.rgb, vec3(0.0, 0.0, 0.0), shadow_intensity * max_darkness);
// 
// 	gl_FragColor = vec4(final_rgb, color.a * tint.a);
// }

varying mediump vec2 var_texcoord0;
varying mediump float var_rot;
varying mediump vec2 var_local_pos; // Локальные координаты пикселя (после искажений)

uniform highp vec4 time_vec;   // x = time
uniform highp vec4 hit_params; // x = is_hit, y = intensity, z = flash_speed

uniform lowp sampler2D texture_sampler;
uniform lowp vec4 tint;
uniform highp vec4 cursor_data; // x=mouse_x, y=mouse_y, z=intensity

void main()
{
	// 1. ПАРАЛЛАКС
	// Сдвигаем UV против движения мыши
	vec2 parallax = cursor_data.xy * 0.00001 * cursor_data.z;
	lowp vec4 color = texture2D(texture_sampler, var_texcoord0 - parallax);

	if (color.a < 0.01) discard;

	// Тень от переворота
	float angle = abs(var_rot); 
	float shadow_flip = 1.0 - smoothstep(0.6, 0.9, angle);
	vec3 rgb = mix(color.rgb * tint.rgb, vec3(0.0), shadow_flip * 0.6);

	// === ЭФФЕКТ ВСПЫШКИ / ПОДСВЕТКИ ===
	if (hit_params.x > 0.5) // Если эффект активен
	{
		float flash = 0.0;
		vec3 flash_color = vec3(0.0);

		if (hit_params.x > 1.5) 
		{
			// === РЕЖИМ HOVER (ЗЕЛЕНЫЙ) ===
			// ИЗМЕНЕНИЕ ЗДЕСЬ:
			// Вместо диапазона [0.0 ... 1.0], делаем [0.4 ... 1.0].
			// sin(...) дает от -1 до 1.
			// * 0.3 дает от -0.3 до 0.3.
			// + 0.7 сдвигает в диапазон от 0.4 до 1.0.
			// Результат: Зеленый цвет никогда не исчезает полностью.
			flash = sin(time_vec.x * hit_params.z) * 0.2 + 0.8;

			flash_color = vec3(0.2, 1.0, 0.2); // Зеленый
		} 
		else 
		{
			// === РЕЖИМ HIT (КРАСНЫЙ) ===
			// Оставляем как было: от 0.0 до 1.0 (полное затухание)
			flash = sin(time_vec.x * hit_params.z) * 0.5 + 0.5;
			flash_color = vec3(1.0, 0.2, 0.2); // Красный
		}

		// Применяем
		rgb = mix(rgb, flash_color, flash * hit_params.y * 0.8);
	}

	// 2. БЛИКИ НА ГРАНЯХ (RIM LIGHT)
	if (cursor_data.z > 0.01)
	{
		// Вектор от центра карты к текущему пикселю
		vec2 to_pixel = normalize(var_local_pos);
		// Вектор от центра карты к мыши
		vec2 to_mouse = normalize(cursor_data.xy);

		// Совпадение направлений (свет падает со стороны мыши)
		float light = max(0.0, dot(to_pixel, to_mouse));
		light = pow(light, 4.0); // Делаем блик узким

		// Маска рамки (только края карты)
		// Настраиваем под размер карты: например, от 60px до 85px от центра
		float dist = length(var_local_pos);
		float border = smoothstep(35.0, 65.0, dist) * (1.0 - smoothstep(75.0, 95.0, dist));

		// Упрощенный вариант: просто чем дальше от центра, тем сильнее (без внешней границы)
		// float border = smoothstep(5.0, 95.0, dist);

		// Рисуем
		rgb += vec3(1.0) * light * border * 0.8 * cursor_data.z;
	}


// ВРЕМЕННЫЙ ТЕСТОВЫЙ БЛОК
// Убрали проверку cursor_data.z > 0.01, чтобы видеть эффект всегда, если cursor_data передан
// if (true)
// {
// 	vec2 to_pixel = normalize(var_local_pos);
// 	vec2 to_mouse = normalize(cursor_data.xy);
// 
// 	// Расчет света
// 	float light = max(0.0, dot(to_pixel, to_mouse));
// 
// 	// ДЕЛАЕМ БЛИК ШИРОКИМ ПО УГЛУ (было 4.0, ставим 1.0)
// 	light = pow(light, 1.0); 
// 
// 	float dist = length(var_local_pos);
// 
// 	// ДЕЛАЕМ РАМКУ ОЧЕНЬ ТОЛСТОЙ
// 	// Начало от 10.0 пикселей от центра (было 55.0)
// 	float border = smoothstep(10.0, 95.0, dist);
// 
// 	// ЯДОВИТЫЙ ЦВЕТ (Фиолетовый) и ДИКАЯ ЯРКОСТЬ (* 5.0)
// 	// Убрали множитель cursor_data.z, чтобы блик был даже если мышка не двигается (но координаты нужны)
// 	vec3 debug_color = vec3(1.0, 0.0, 1.0); 
// 
// 	rgb += debug_color * light * border * 5.0;
// }
	gl_FragColor = vec4(rgb, color.a * tint.a);
}
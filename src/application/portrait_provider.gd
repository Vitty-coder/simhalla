class_name PortraitProvider
extends RefCounted
## Retrato OPCIONAL con sustituto grafico (PROJECT.md §16): usa `assets/portrait.(png|jpg|jpeg|webp)` del paquete si existe y es una
## imagen valida; si no, genera de forma DETERMINISTA un retrato de sustitucion (color y iniciales derivados del id). Sin red ni
## recursos externos.

const SIZE := 96
const NAMES := ["portrait.png", "portrait.jpg", "portrait.jpeg", "portrait.webp"]


## Color estable por id (hash FNV del texto -> tono).
static func color_of(id: String) -> Color:
	var h := Rng.fnv1a64(id)
	return Color.from_hsv(float((h >> 8) & 0xFF) / 255.0, 0.45 + float((h >> 20) & 0x3F) / 255.0, 0.62 + float((h >> 28) & 0x1F) / 255.0)


## Iniciales (hasta 2 letras) del nombre o id.
static func initials(name: String) -> String:
	var words: PackedStringArray = name.replace("/", " ").replace("_", " ").replace("-", " ").strip_edges().split(" ", false)
	if words.is_empty():
		return "?"
	var s := (words[0] as String).substr(0, 1).to_upper()
	if words.size() > 1:
		s += (words[1] as String).substr(0, 1).to_upper()
	elif (words[0] as String).length() > 1:
		s += (words[0] as String).substr(1, 1).to_lower()
	return s


## Imagen de sustitucion (SIZE x SIZE): fondo del color del id con un disco mas claro y barra inferior; sin texto (el
## nombre se muestra aparte en la interfaz, asi no depende de fuentes).
static func placeholder(id: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var c := color_of(id)
	img.fill(c.darkened(0.25))
	var center := Vector2(SIZE / 2.0, SIZE / 2.0 - 6.0)
	for y in SIZE:
		for x in SIZE:
			if Vector2(x, y).distance_to(center) < 26.0:
				img.set_pixel(x, y, c.lightened(0.3))
			elif y > SIZE - 26 and Vector2(x, y).distance_to(Vector2(SIZE / 2.0, SIZE + 18.0)) < 58.0:
				img.set_pixel(x, y, c.lightened(0.15))
	return img


## Imagen del retrato desde los archivos de un paquete ({ruta: bytes}) o el sustituto. {"image", "from_package": bool}.
static func load_image(id: String, package_files: Dictionary = {}) -> Dictionary:
	for n in NAMES:
		var key: String = "assets/" + str(n)
		if package_files.has(key):
			var img := Image.new()
			var bytes: PackedByteArray = package_files[key]
			var err := ERR_FILE_UNRECOGNIZED
			match n.get_extension():
				"png":
					err = img.load_png_from_buffer(bytes)
				"jpg", "jpeg":
					err = img.load_jpg_from_buffer(bytes)
				"webp":
					err = img.load_webp_from_buffer(bytes)
			if err == OK and img.get_width() > 0 and img.get_width() <= 4096 and img.get_height() <= 4096:
				return {"image": img, "from_package": true}
	return {"image": placeholder(id), "from_package": false}


static func texture(id: String, package_files: Dictionary = {}) -> ImageTexture:
	return ImageTexture.create_from_image(load_image(id, package_files)["image"])

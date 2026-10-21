extends Node


@export var mod_id: String = ""
@export var pack_name: = "mod"
@export var pack_zip: = false
@export var separate_cache_pack: = true
@export var create_distribution_zip: = true

@export var ignored_files: Array[String] = [
	"mod.json", 
]

@export var ignored_directories: Array[String] = [
	".build_include"
]

@export var ignored_extensions: Array[String] = [
	"pck", 
	"zip", 
	"authoring", 
	"ignore", 
]


func _ready() -> void :
	var pack: = PackMeta.new()

	var mod_folder: = "res://mods/%s" % mod_id
	for file in FileUtil.get_file_paths_recursive(mod_folder):
		var base_dir: = file.trim_prefix(mod_folder + "/").get_base_dir()
		var ignore_file: = false
		for ignored_directory in ignored_directories:
			if base_dir.begins_with(ignored_directory):
				ignore_file = true
				break

		if ignore_file:
			continue

		var file_name: = file.get_file()
		if file_name not in ignored_files and file_name.get_extension() not in ignored_extensions:
			pack.pack_file(file)

	var pack_extension: = "pck"
	if pack_zip:
		pack_extension = "zip"

	var cache_pack_path: String = ""
	if separate_cache_pack:
		cache_pack_path = "res://mods/%s/cache.%s" % [mod_id, pack_extension]

	var pack_path: = "res://mods/%s/%s.%s" % [mod_id, pack_name, pack_extension]
	if pack_zip:
		pack.pack_zip(pack_path, cache_pack_path)
	else:
		pack.pack_pck(pack_path, cache_pack_path)

	if create_distribution_zip:
		var zip_packer: = ZIPPacker.new()
		zip_packer.open("res://mods/%s/%s.zip" % [mod_id, mod_id])
		zip_packer.start_file("%s/mod.json" % mod_id)
		zip_packer.write_file(FileAccess.get_file_as_bytes("res://mods/%s/mod.json" % [mod_id]))
		zip_packer.close_file()

		zip_packer.start_file("%s/%s.%s" % [mod_id, pack_name, pack_extension])
		zip_packer.write_file(FileAccess.get_file_as_bytes(pack_path))
		zip_packer.close_file()

		if cache_pack_path != "":
			zip_packer.start_file("%s/cache.%s" % [mod_id, pack_extension])
			zip_packer.write_file(FileAccess.get_file_as_bytes(cache_pack_path))
			zip_packer.close_file()

		var build_include_dir: = "res://mods/%s/.build_include" % mod_id
		if DirAccess.dir_exists_absolute(build_include_dir):
			var filepaths: = FileUtil.get_file_paths_recursive(build_include_dir)
			for filepath in filepaths:
				var relative_path: = filepath.trim_prefix(build_include_dir)
				zip_packer.start_file(mod_id.path_join(relative_path))
				zip_packer.write_file(FileAccess.get_file_as_bytes(filepath))
				zip_packer.close_file()

		zip_packer.close()

	get_tree().quit()


class PackMeta extends RefCounted:
	var packed_files: Array[String] = []
	var packed_resource_uids: Array[int] = []
	var packed_resource_files: Array[String] = []

	var global_classes: Array = []


	func pack_file(file: String) -> void :
		if ResourceLoader.exists(file):
			var uid: = ResourceLoader.get_resource_uid(file)
			packed_resource_files.append(file)
			packed_resource_uids.append(uid)

			var import_path: = file + ".import"
			if FileAccess.file_exists(import_path):
				packed_files.append(import_path)

				var config: = ConfigFile.new()
				config.load(import_path)
				var remapped_path: Variant = config.get_value("remap", "path", "")

				if remapped_path is String and remapped_path != "":
					packed_files.append(remapped_path)
			else:
				packed_files.append(file)

			if ResourceLoader.exists(file, "Script"):
				for global_class in ProjectSettings.get_global_class_list():
					if global_class.path == file:
						global_classes.append(global_class)
		else:
			packed_files.append(file)


	func get_global_classes_buffer() -> PackedByteArray:
		var config: = ConfigFile.new()
		config.set_value("", "list", global_classes)
		return config.encode_to_text().to_utf8_buffer()


	func get_uid_cache() -> PackedByteArray:
		var buffer: = StreamPeerBuffer.new()

		buffer.put_u32(packed_resource_uids.size())
		for i in packed_resource_uids.size():
			buffer.put_64(packed_resource_uids[i])
			buffer.put_32(len(packed_resource_files[i]))
			buffer.put_data(packed_resource_files[i].to_utf8_buffer())

		return buffer.data_array


	func write_zip_file(packer: ZIPPacker, file: String, bytes: PackedByteArray) -> void :
		packer.start_file(file)
		packer.write_file(bytes)
		packer.close_file()


	func pack_zip(path: String, cache_path: String = "") -> void :
		var packer: = ZIPPacker.new()
		packer.open(path)

		for file in packed_files:
			write_zip_file(packer, file.trim_prefix("res://"), FileAccess.get_file_as_bytes(file))

		if cache_path != "":
			packer.close()
			packer = ZIPPacker.new()
			packer.open(cache_path)

		if not global_classes.is_empty():
			write_zip_file(packer, ".godot/global_script_class_cache.cfg", get_global_classes_buffer())

		if not packed_resource_uids.is_empty():
			write_zip_file(packer, ".godot/uid_cache.bin", get_uid_cache())

		packer.close()


	func pack_pck(path: String, cache_path: String = "") -> void :
		var packer: = PCKPacker.new()
		packer.pck_start(path)

		for file in packed_files:
			packer.add_file(file, file)

		if cache_path != "":
			packer.flush()
			packer = PCKPacker.new()
			packer.pck_start(cache_path)

		if not global_classes.is_empty():
			packer.add_file_from_buffer("res://.godot/global_script_class_cache.cfg", get_global_classes_buffer())

		if not packed_resource_uids.is_empty():
			packer.add_file_from_buffer("res://.godot/uid_cache.bin", get_uid_cache())

		packer.flush()

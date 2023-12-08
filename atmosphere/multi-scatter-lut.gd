@tool
extends Texture2DRD

var texture_size := Vector2i(32, 32)

var rd : RenderingDevice

var shader : RID
var pipeline : RID

# We use 3 textures:
# - One to render into
# - One that contains the last frame rendered
# - One for the frame before that
var texture_rd : RID
var texture_set : RID

var transmittance_tex := load("res://atmosphere/transmittance_lut.tres")

func _init():
	RenderingServer.call_on_render_thread(_initialize_compute_code)

func _create_uniform_set(texture_rd : RID) -> RID:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rd)
	return rd.uniform_set_create([uniform], shader, 0)
	
func _create_uniform_set_for_sampling(texture_rd : RID) -> RID:
	var sampler_state = RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	
	var sampler = rd.sampler_create(sampler_state)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = 0
	uniform.add_id(sampler)
	uniform.add_id(texture_rd)
	return rd.uniform_set_create([uniform], shader, 1)

func _initialize_compute_code():
	# As this becomes part of our normal frame rendering,
	# we use our main rendering device here.
	rd = RenderingServer.get_rendering_device()

	# Create our shader
	var shader_file = load("res://atmosphere/multi-scattering-lut.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	if not shader.is_valid():
		print("you got an invalid shader buddy")
		return
	pipeline = rd.compute_pipeline_create(shader)

	# Create our textures to manage our wave
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size.x
	tf.height = texture_size.y
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT + RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT

	# Create our texture
	texture_rd = rd.texture_create(tf, RDTextureView.new(), [])
	# Now create our uniform set so we can use these textures in our shader
	texture_set = _create_uniform_set(texture_rd)
	var transmittance_set = _create_uniform_set_for_sampling(transmittance_tex.texture_rd)

	texture_rd_rid = texture_rd

	var push_constant : PackedFloat32Array = PackedFloat32Array()
	push_constant.push_back(texture_size.x)
	push_constant.push_back(texture_size.y)
	push_constant.push_back(0.0)
	push_constant.push_back(0.0)

	# Run our compute shader.
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_bind_uniform_set(compute_list, texture_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, transmittance_set, 1)
	rd.compute_list_dispatch(compute_list, 4, 4, 1)
	rd.compute_list_end()
slangc ./assets/shaders/Main.slang -profile spirv_1_6 -target spirv -o ./assets/shaders/main.vert.spv -entry vert
slangc ./assets/shaders/Main.slang -profile spirv_1_6 -target spirv -o ./assets/shaders/main.frag.spv -entry frag
slangc ./assets/shaders/Light.slang -profile spirv_1_6 -target spirv -o ./assets/shaders/light.vert.spv -entry vert
slangc ./assets/shaders/Light.slang -profile spirv_1_6 -target spirv -o ./assets/shaders/light.frag.spv -entry frag
slangc ./assets/shaders/Pre.slang -profile spirv_1_6 -target spirv -o ./assets/shaders/pre.comp.spv -entry "comp"
slangc ./assets/shaders/Post.slang -profile spirv_1_6 -target spirv -o ./assets/shaders/post.comp.spv -entry "comp"
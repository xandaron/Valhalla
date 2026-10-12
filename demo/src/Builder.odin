package Demo

import Valhalla "../../src"

Builder :: struct {
	spine: BuilderNode,
}

BuilderNodeType :: enum {
	Spine,
	Limb,
}

BuilderNode :: struct {
	type: BuilderNodeType,
	modelIdx: u32,
	instanceIdx: u32,
	parent: ^BuilderNode,
	children: []BuilderNode,
}

setup :: proc(scene: ^Scene) -> (builder: Builder) {
	body := getModel(scene, "Body")
	addObject()
	Valhalla.addInstance()
	return
}

// Attaches a node to a taret node.
attach :: proc(builder: ^Builder, target, node: ^BuilderNode) {
	assert(builder != nil)
	assert(target != nil)
	assert(node != nil)
	assert(node.type != .Spine)
}
package Demo

import Valhalla "../../src"

// ===[ Maths ]==================================================================

Vec2 :: Valhalla.Vec2
Vec3 :: Valhalla.Vec3
Vec4 :: Valhalla.Vec4
Quat :: Valhalla.Quat
Mat3 :: Valhalla.Mat3
Mat4 :: Valhalla.Mat4

PI :: Valhalla.PI
IMAT4 :: Valhalla.IMAT4
IQUAT :: Valhalla.IQUAT

atan2 :: Valhalla.atan2
cos :: Valhalla.cos
cross :: Valhalla.cross
dot :: Valhalla.dot
floor :: Valhalla.floor
inverse :: Valhalla.inverse
length :: Valhalla.length
length2 :: Valhalla.length2
lerp :: Valhalla.lerp
maxVec3 :: Valhalla.maxVec3
minVec3 :: Valhalla.minVec3
normalize :: Valhalla.normalize
quatFromAxisAngle :: Valhalla.quatFromAxisAngle
radians :: Valhalla.radians
rotate3 :: Valhalla.rotate3
sign :: Valhalla.sign
sin :: Valhalla.sin
slerp :: Valhalla.slerp
sqrt :: Valhalla.sqrt
transform :: Valhalla.transform

// ===[ Lifecycle ]==============================================================

GraphicsData :: Valhalla.GraphicsData
InitGraphicsInfo :: Valhalla.InitGraphicsInfo
GraphicsError :: Valhalla.Error

initGraphics :: Valhalla.initGraphics
cleanupGraphics :: Valhalla.cleanupGraphics
compileShader :: Valhalla.compileShader
drawFrame :: Valhalla.drawFrame

// ===[ Configuration ]==========================================================

RenderSettings :: Valhalla.RenderSettings
WindowSettings :: Valhalla.WindowSettings

SHADOW_CUBE_FACES :: Valhalla.SHADOW_CUBE_FACES

defaultRenderSettings :: Valhalla.defaultRenderSettings
frameLatencyLimit :: Valhalla.frameLatencyLimit

// ===[ Window and Input ]=======================================================

InputEvent :: Valhalla.InputEvent
CharEvent :: Valhalla.CharEvent
CursorEnterEvent :: Valhalla.CursorEnterEvent
CursorPosEvent :: Valhalla.CursorPosEvent
FocusEvent :: Valhalla.FocusEvent
KeyEvent :: Valhalla.KeyEvent
MouseButtonEvent :: Valhalla.MouseButtonEvent
ScrollEvent :: Valhalla.ScrollEvent

handleInput :: Valhalla.handleInput
imguiWantsKeyboard :: Valhalla.imguiWantsKeyboard
imguiWantsMouse :: Valhalla.imguiWantsMouse
cursorToRenderNDC :: Valhalla.cursorToRenderNDC
renderNDCToCursor :: Valhalla.renderNDCToCursor
requestClose :: Valhalla.requestClose
updateWindow :: Valhalla.updateWindow
windowGeometry :: Valhalla.windowGeometry
windowSize :: Valhalla.windowSize

// ===[ Swapchain ]==============================================================

getRenderAspectRatio :: Valhalla.getRenderAspectRatio
hdrActive :: Valhalla.hdrActive
hdrAvailable :: Valhalla.hdrAvailable
hdrEnabled :: Valhalla.hdrEnabled
setHDREnabled :: Valhalla.setHDREnabled

// ===[ Scene Data ]=============================================================

AABB :: Valhalla.AABB
Vertex :: Valhalla.Vertex
TextureIndex :: Valhalla.TextureIndex
Mesh :: Valhalla.Mesh
Bindpoint :: Valhalla.Bindpoint
Attachment :: Valhalla.Attachment

DIRTY_ALL :: Valhalla.DIRTY_ALL
DIRTY_GEOMETRY :: Valhalla.DIRTY_GEOMETRY

addInstance :: Valhalla.addInstance
changeModel :: Valhalla.changeModel
objectTransform :: Valhalla.objectTransform
objectParentTransform :: Valhalla.objectParentTransform
markCommandsDirty :: Valhalla.markCommandsDirty
updateSceneBuffers :: Valhalla.updateSceneBuffers
updateSceneData :: Valhalla.updateSceneData

// ===[ Textures ]===============================================================

addImages :: Valhalla.addImages
changeTextureImage :: Valhalla.changeTextureImage
loadImages :: Valhalla.loadImages
texturePreview :: Valhalla.texturePreview

// ===[ Animation ]==============================================================

Bone :: Valhalla.Bone
Animation :: Valhalla.Animation
AnimationNode :: Valhalla.AnimationNode
KeyValue :: Valhalla.KeyValue
InterpolationType :: Valhalla.InterpolationType
AnimationBehavior :: Valhalla.AnimationBehavior
AnimationTransition :: Valhalla.AnimationTransition
ObjectAnimation :: Valhalla.ObjectAnimation
ObjectAnimationCache :: Valhalla.ObjectAnimationCache
ObjectAnimationEnd :: Valhalla.ObjectAnimationEnd

// ===[ Camera ]=================================================================

view :: Valhalla.view
projection :: Valhalla.projection
viewProjection :: Valhalla.viewProjection

// ===[ Debug Images and Screenshots ]===========================================

DebugImage :: Valhalla.DebugImage

DEBUG_IMAGE_NAMES := Valhalla.DEBUG_IMAGE_NAMES

debugImageInfo :: Valhalla.debugImageInfo
debugPreview :: Valhalla.debugPreview
requestDebugDump :: Valhalla.requestDebugDump
requestScreenshot :: Valhalla.requestScreenshot
screenshotPending :: Valhalla.screenshotPending
screenshotRange :: Valhalla.screenshotRange
screenshotSaved :: Valhalla.screenshotSaved

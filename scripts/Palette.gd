extends Node
## 全局配色常量
## 与 ui_prototype/index.html 顶部的 CSS 变量一一对应

const BA_BLUE := Color("#5ea7ff")
const BA_BLUE_SOFT := Color("#9cc9ff")
const BA_SKY := Color("#dceeff")
const BA_DEEP := Color("#2b4a6f")
const BA_TEXT := Color("#2c4a6e")
const BA_TEXT_DIM := Color("#6d8cae")
const BA_CARD := Color(1, 1, 1, 0.62)
const BA_CARD_STRONG := Color(1, 1, 1, 0.82)
const BA_CARD_TINT := Color(220.0 / 255.0, 238.0 / 255.0, 255.0 / 255.0, 0.72)
const BA_BORDER := Color(1, 1, 1, 0.85)
const BA_BORDER_BLUE := Color(94.0 / 255.0, 167.0 / 255.0, 255.0 / 255.0, 0.35)
const BA_SHADOW := Color(120.0 / 255.0, 160.0 / 255.0, 210.0 / 255.0, 0.28)
const SHADOW_BLUE := Color(94.0 / 255.0, 167.0 / 255.0, 255.0 / 255.0, 0.35)

## 渐变（头像 / Logo / 主按钮）
const GRAD_BLUE_FROM := Color("#8cc2ff")
const GRAD_BLUE_TO := Color("#5ea7ff")
const GRAD_ORANGE_FROM := Color("#ffd19a")
const GRAD_ORANGE_TO := Color("#ffb36b")
const PRIMARY_HOVER := Color("#6cb0ff")

## 存档槽按钮
const SLOT_LOAD := Color("#4caf85")
const SLOT_SAVE := Color("#5ea7ff")
const SLOT_DELETE := Color("#e0685a")

## 遮罩
const OVERLAY_BG := Color(140.0 / 255.0, 180.0 / 255.0, 230.0 / 255.0, 0.35)

## 通用圆角
const RADIUS := 18

## 输入框占位文字颜色（rgba(90,125,165,.4)）
const PLACEHOLDER := Color(90.0 / 255.0, 125.0 / 255.0, 165.0 / 255.0, 0.4)
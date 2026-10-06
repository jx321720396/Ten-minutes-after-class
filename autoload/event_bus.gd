extends Node
## EventBus 单例：全局信号总线（§4.1）。模拟内核 → 表现层的唯一通道。
##
## 只声明信号、不承载玩法规则；信号名用过去式，载荷用字典 / 基础类型，
## 便于日志复用（架构总览 §4）。

signal event_happened(payload: Dictionary)
signal day_settled(summary: Dictionary)
signal tag_changed(id: int, tag: String)
signal stress_burst(i: int)

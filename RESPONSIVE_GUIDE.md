# RESPONSIVE GUIDE  
继续完善 APP 与 PC 端的界面差异：实现响应式布局和断点、调整教师中心页面在窄屏与宽屏下的组件排列、优化触控交互（更大可点目标）并确保鼠标悬停/焦点样式在 PC 上可用。  
  
示例（Flutter）：  
- 使用 LayoutBuilder 根据宽度选择不同布局  
- 在触控界面增大按钮最小可触区域（minSize/InkWell）  

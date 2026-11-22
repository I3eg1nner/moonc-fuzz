struct Node {
  l : Option[Node]
  r : Option[Node]
}
func op_add(self : Node, other : Node) -> Node {
  { l: Some(self), r: Some(other) }
}
func init {
  let aLeafWithLongName = { l: Option::None, r: Option::None }
  let tree = aLeafWithLongName + aLeafWithLongName + aLeafWithLongName + aLeafWithLongName + aLeafWithLongName
  "hello".print()
}

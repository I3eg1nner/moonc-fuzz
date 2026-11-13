trait Shape {
  area(Self) -> Int
}
struct Sq { s : Int }
struct Rect { w : Int; h : Int }
impl Shape for Sq with area(self) { self.s * self.s }
impl Shape for Rect with area(self) { self.w * self.h }
fn compute() -> String {
  let shapes : Array[&Shape] = [Sq::{ s: 3 }, Rect::{ w: 2, h: 5 }]
  let mut total = 0
  for s in shapes {
    total = total + s.area()
  }
  total.to_string()
}
fn main { println(compute()) }

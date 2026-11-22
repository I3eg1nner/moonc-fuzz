trait T21 { f(Self) -> Int }
struct S21 { x21 : Int }
impl T21 for S21 with f(self) { self.x21 }
impl T21 for S21 with f(self) { self.x21 }
fn main { println(S21::{x21:21}.f()) }

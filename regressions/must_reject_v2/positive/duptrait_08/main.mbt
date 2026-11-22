trait T8 { f(Self) -> Int }
struct S8 { x8 : Int }
impl T8 for S8 with f(self) { self.x8 }
impl T8 for S8 with f(self) { self.x8 }
fn main { println(S8::{x8:8}.f()) }

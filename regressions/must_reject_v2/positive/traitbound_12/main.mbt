trait T12 { f(Self) -> Int }
struct S12 { x12 : Int }
fn[A : T12] g(a : A) -> Int { a.f() }
fn main { println(g(S12::{x12:12})) }

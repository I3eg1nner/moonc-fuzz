trait T16 { f(Self) -> Int }
struct S16 { x16 : Int }
fn[A : T16] g(a : A) -> Int { a.f() }
fn main { println(g(S16::{x16:16})) }

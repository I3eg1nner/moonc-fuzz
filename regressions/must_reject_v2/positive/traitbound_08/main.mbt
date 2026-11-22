trait T8 { f(Self) -> Int }
struct S8 { x8 : Int }
fn[A : T8] g(a : A) -> Int { a.f() }
fn main { println(g(S8::{x8:8})) }

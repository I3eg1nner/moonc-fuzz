enum E24 { A; B }
fn f(e : E24) -> Int { match e { A => 24 } }
fn main { println(f(A)) }

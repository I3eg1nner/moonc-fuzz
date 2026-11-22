enum E28 { A; B }
fn f(e : E28) -> Int { match e { A => 28 } }
fn main { println(f(A)) }

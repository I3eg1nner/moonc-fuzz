enum K {
  A(Int)
}

#valtype
struct E {
  id : Int
  k : K
}

fn main {
  let xs : Array[E] = []
  xs.push({ id: 0, k: K::A(0) })
  println(xs.length())
}

enum Kind {
  Ref(String)
}

#valtype
struct Entry {
  id : Int
  kind : Kind
}

fn main {
  let values : Array[Entry] = []
  values.push({ id: 0, kind: Kind::Ref("x") })
  println(values[0].id)
}

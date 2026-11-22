extern "C" fn store_v128(address : UInt64, value : V128) -> Unit = "repro_store_v128"

pub fn store(x : Float) -> Unit {
  store_v128(0UL, @v128.f32x4_const(x, x, x, x))
}

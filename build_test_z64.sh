cd polkavm
cargo build --release
cd ..
bash build_riscv64
mkdir -p guests_out
./polkavm/target/release/polkatool link  ./zig-out/bin/test_z -o guests_out/test_z64.pvm

cd polkavm
cargo build --release
cd ..
bash build_riscv32
mkdir -p guests_out
./polkavm/target/release/polkatool link  ./zig-out/bin/test_z -o guests_out/test_z32.pvm

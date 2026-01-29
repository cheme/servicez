cd polkavm
#cargo build --release -p polkatool
cargo build -p polkatool
cd ..
bash build_riscv64
mkdir -p guests_out
./polkavm/target/debug/polkatool link  ./zig-out/bin/test_z -o guests_out/test_z64.pvm
./polkavm/target/debug/polkatool link  ./zig-out/bin/example-hello-world -o  guests_out/hello64.pvm
./polkavm/target/debug/polkatool link  ./zig-out/bin/mt -o guests_out/mt64.pvm
#./polkavm/target/debug/polkatool link  ./zig-out/bin/example-hello-world -o polkavm/guest-programs/output/example-hello-world.polkavm
#cd polkavm
#cargo run -p hello-world-host

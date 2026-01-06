cd polkavm
#cargo build --release -p polkatool
cargo build -p polkatool
cd ..
bash build_riscv32
mkdir -p guests_out
#./polkavm/target/release/polkatool link  ./zig-out/bin/test_z -o guests_out/test_z32.pvm
#./polkavm/target/release/polkatool link  ./zig-out/bin/example-hello-world -o polkavm/guest-programs/output/example-hello-world.polkavm
./polkavm/target/debug/polkatool link  ./zig-out/bin/test_z -o guests_out/test_z32.pvm
./polkavm/target/debug/polkatool link  ./zig-out/bin/example-hello-world -o polkavm/guest-programs/output/example-hello-world.polkavm
./polkavm/target/debug/polkatool link  ./zig-out/bin/mt -o guests_out/mt32.pvm
cd polkavm
cargo run -p hello-world-host

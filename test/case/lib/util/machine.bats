bats_require_minimum_version 1.5.0
load ../../../../src/lib/util/machine.sh

assert_pid() {
	name=$1
	pid=${name##*.}
	[[ $pid =~ ^[0-9]+$ ]]
}

assert_name() {
	name=$1
	expected=$2
	name=${name%.*}
	[[ $name == $expected ]]
}

@test "machine_name short" {
	run machine_name foo
	assert_pid "$output"
	assert_name "$output" bats-exec-test-foo
}

@test "machine_name with dot" {
	run machine_name foo.bar
	assert_pid "$output"
	assert_name "$output" bats-exec-test-foo.bar
}

@test "machine_name repeating dot" {
	run machine_name foo..bar
	assert_pid "$output"
	assert_name "$output" bats-exec-test-foo.bar
}

@test "machine_name repeating dash" {
	run machine_name foo--bar
	assert_pid "$output"
	assert_name "$output" bats-exec-test-foo-bar
}

@test "machine_name max hostname length" {
	run machine_name 1234567890abcdefghijklmnopqrstuvwxyz12345xxx
	assert_pid "$output"
	assert_name "$output" bats-exec-test-1234567890abcdefghijklmnopqrstuvwxyz12345
}

@test "machine_name strip dash suffix" {
	run machine_name 1234567890abcdefghijklmnopqrstuvwxyz1234-xxx
	assert_pid "$output"
	assert_name "$output" bats-exec-test-1234567890abcdefghijklmnopqrstuvwxyz1234
}

@test "machine_name strip dot suffix" {
	run machine_name 1234567890abcdefghijklmnopqrstuvwxyz1234.xxx
	assert_pid "$output"
	assert_name "$output" bats-exec-test-1234567890abcdefghijklmnopqrstuvwxyz1234
}

@test "machine_name normalize trailing plus/dash" {
	run machine_name foo+++
	assert_pid "$output"
	assert_name "$output" bats-exec-test-foo
}

@test "machine_name strip trailing dot" {
	run machine_name foo...
	assert_pid "$output"
	assert_name "$output" bats-exec-test-foo
}

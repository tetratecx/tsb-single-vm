#!/usr/bin/env bats

@test "Check vmtsb.sh exists and is accessible" {
  run ls -l ../vmtsb.sh
}

@test "Test no arguments" {
  run bash ../vmtsb.sh vmtsb
  echo "STATUS: $status"
  [ "$status" -eq 1 ]
}

@test "Test invalid argument" {
  run bash ../vmtsb.sh -m
  [ "$status" -eq 1 ]
}

@test "Test empty owner argument" {
  run bash ../vmtsb.sh -o
  [ "$status" -eq 1 ]
}

@test "Test get the help message" {
  run bash ../vmtsb.sh -h
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"Usage:"* ]]
}

@test "Test listing all instances" {
  run bash ../vmtsb.sh -l
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"Listing all instances from Owner: all"* ]]
}

@test "Test owner with no action argument" {
  run bash ../vmtsb.sh -o ric

    echo "Comparing line:\n${lines[0]}"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"Listing all instances from Owner ric"* ]]
}

@test "Test owner with action argument" {
  run bash ../vmtsb.sh -o ric -a suspend

    echo "Comparing line:\n${output}"

  [ "$status" -eq 0 ]
  [[ "${output}" == *"Working on instances:"* ]]
  [[ "${output}" == *"Suspending instance(s)"* ]]
}

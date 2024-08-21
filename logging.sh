#!/bin/bash

function echo_green() {
  local lightgreen='\033[1;32m'
  local nocolor='\033[0m'
  echo -e "${lightgreen}$1${nocolor}"
}

function echo_red() {
  local lightred='\033[1;31m'
  local nocolor='\033[0m'
  echo -e "${lightred}$1${nocolor}"
}

function log_good() {
  echo_green "[$0] $1" 
}

function log() {
  local lightgrey='\033[0;37m'
  local darkgrey='\033[1;30m'
  local nocolor='\033[0m'
  echo -e "${darkgrey}[$0] $1${nocolor}" 
}

function log_bad() {
  echo_red "[$0] $1" 
}

function div() {
  echo "---"
}

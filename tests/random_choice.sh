##############################
# Final solution without collision concerns:

is_id() {
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]
}

schoice() {
    is_id "$1" && is_id "$2" || return 1
    eval set "$1" "$2" "\${#$2[@]}"
    eval "$1=\${$2[$((RANDOM%$3))]}"
}

lchoice() {
    is_id "$1" && is_id "$2" || return 1
    eval set "$1" "$2" "\${#$2[@]}" $(((RANDOM<<15)+RANDOM))
    eval "$1=\${$2[$(($4%$3))]}"
}

# Can program like this throughout, using only one (global) variable, say RET, to allow
# obtaining string result from function calls 


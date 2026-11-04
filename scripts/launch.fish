#!/usr/bin/env -S fish --no-config
# Runs the command that starts a bbrf node (`elixir -S mix run --no-halt`, `bin/bbrf start`)
# with the distribution its BBRF_ROLE needs:
#
#   all          plain distribution, -sname $NODE (default bbrf)
#   hub, ingest  TLS distribution (see server-next/README.md): decrypts the node's
#                $SECRETS_DIR/<role>.enc.yaml with its age key into RUNTIME_DIR (the TLS key,
#                the cookie and the TLS option file), then passes the VM flags in
#                ELIXIR_ERL_OPTIONS, which both elixir and releases read
#
# The cookie is never put on a command line or in the environment: the node reads it from
# BBRF_COOKIE_FILE at boot.

function env_or -a var fallback
    if test -n "$$var"
        echo $$var
    else
        echo $fallback
    end
end

function die
    echo "error: $argv" >&2
    exit 1
end

set role (env_or BBRF_ROLE all)
set secrets_dir (env_or SECRETS_DIR secrets)
set age_key_file (env_or AGE_KEY_FILE (env_or XDG_CONFIG_HOME $HOME/.config)/bbrf/age.key)
set port_min (env_or DIST_PORT_MIN 9100)
set port_max (env_or DIST_PORT_MAX 9105)

set -q argv[1]; or die "usage: launch.fish <command that starts the node>"

# releases: the node name and the TLS flags come from ELIXIR_ERL_OPTIONS, not RELEASE_NODE
set -gx RELEASE_DISTRIBUTION none

# hub and ingest: each side trusts only the CA that signs the other side; dud signs nothing
switch $role
    case all
        set -gx ELIXIR_ERL_OPTIONS "-sname "(env_or NODE bbrf)" $ELIXIR_ERL_OPTIONS"
        exec $argv
    case hub
        set server_ca caI
        set client_ca dud
    case ingest
        set server_ca dud
        set client_ca caH
    case '*'
        die "BBRF_ROLE must be hub, ingest or all, got $role"
end

command -q sops; or die "sops not found (it is in the nix devShell)"
set secrets_dir (path resolve $secrets_dir)
set secrets $secrets_dir/$role.enc.yaml
test -f $secrets; or die "$secrets not found; run 'make secrets' on the admin machine and copy secrets/ here"
test -f $age_key_file; or die "no age key at $age_key_file; run 'make age-key'"

set runtime (env_or RUNTIME_DIR (env_or XDG_RUNTIME_DIR /tmp)/bbrf-$role)
mkdir -p $runtime; and chmod 700 $runtime; or die "cannot create $runtime"
umask 077

function decrypt -a field
    SOPS_AGE_KEY_FILE=$age_key_file sops --decrypt --extract "[\"$field\"]" $secrets
    or die "cannot decrypt $secrets with $age_key_file; was it encrypted to this node's age key?"
end

set node (decrypt node)
decrypt key >$runtime/key.pem
decrypt cookie >$runtime/cookie
set host (string replace -r '^[^@]*@' '' -- $node)

# the hub listens on its own address; the ingest node only connects out, so it listens
# on loopback where nothing else can reach it
if test $role = ingest
    set bind 127.0.0.1
else if string match -qr '^[0-9]+(\.[0-9]+){3}$' -- $host
    set bind $host
else
    set bind
end

printf '[{server, [{cacertfile, "%s"}, {certfile, "%s"},
           {keyfile, "%s"}, {secure_renegotiate, true},
           {verify, verify_peer}, {fail_if_no_peer_cert, true}]},
 {client, [{cacertfile, "%s"}, {certfile, "%s"},
           {keyfile, "%s"}, {secure_renegotiate, true},
           {verify, verify_peer}]}].
' \
    $secrets_dir/$server_ca.crt $secrets_dir/$role.crt $runtime/key.pem \
    $secrets_dir/$client_ca.crt $secrets_dir/$role.crt $runtime/key.pem >$runtime/dist.conf

set flags -name $node -proto_dist inet_tls -ssl_dist_optfile $runtime/dist.conf -connect_all false \
    -kernel inet_dist_listen_min $port_min inet_dist_listen_max $port_max
if test -n "$bind"
    set -a flags -kernel inet_dist_use_interface "{"(string replace -a . , $bind)"}"
    # only takes effect when this node is the one starting epmd
    set -gx ERL_EPMD_ADDRESS $bind
end

set -gx ELIXIR_ERL_OPTIONS "$flags $ELIXIR_ERL_OPTIONS"
set -gx BBRF_COOKIE_FILE $runtime/cookie

echo "==> $role node $node, TLS distribution on "(env_or bind "all interfaces")" ports $port_min-$port_max"
exec $argv

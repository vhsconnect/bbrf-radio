#!/usr/bin/env fish
# Certificates and secrets for a hub + ingest deployment (see server-next/README.md).
#
#   secrets.fish age-key   on each node: create its age key if missing, print the public key
#   secrets.fish init      on the admin machine: CAs, node certificates, cookie, encrypted node files
#   secrets.fish check     verify the files in SECRETS_DIR
#
# Every prompt can be answered from the environment instead:
#   HUB_ADDR, INGEST_ADDR   the address (IP or hostname) each node's distribution listens on
#   HUB_AGE, INGEST_AGE     each node's age public key, from `secrets.fish age-key` on that node
#   FORCE=1                 replace existing files without asking

function env_or -a var fallback
    if test -n "$$var"
        echo $$var
    else
        echo $fallback
    end
end

set secrets_dir (env_or SECRETS_DIR secrets)
set ca_dir (env_or CA_DIR (env_or XDG_DATA_HOME $HOME/.local/share)/bbrf/ca)
set age_key_file (env_or AGE_KEY_FILE (env_or XDG_CONFIG_HOME $HOME/.config)/bbrf/age.key)
# where sops itself looks for the admin's key
set admin_age_key_file (env_or SOPS_AGE_KEY_FILE (env_or XDG_CONFIG_HOME $HOME/.config)/sops/age/keys.txt)
set ca_days (env_or CA_DAYS 1825)
set node_days (env_or NODE_DAYS 365)

function die
    echo "error: $argv" >&2
    exit 1
end

function say
    echo "==> $argv"
end

function need
    for tool in $argv
        command -q $tool; or die "$tool not found (it is in the nix devShell: nix develop)"
    end
end

function ask -a var prompt check
    set -l value $$var
    while test -z "$value"; or begin
            test -n "$check"; and not string match -qr -- $check $value
        end
        isatty stdin; or die "$var is not set"
        read -P "$prompt: " value; or die "no answer for $var"
    end
    set -g $var $value
end

function confirm -a question
    test "$FORCE" = 1; and return 0
    isatty stdin; or die "$question (set FORCE=1 to go ahead)"
    read -l -P "$question [y/N] " answer
    contains -- "$answer" y Y
end

function san -a addr
    if string match -qr '^[0-9.]+$' -- $addr; or string match -q '*:*' -- $addr
        echo IP:$addr
    else
        echo DNS:$addr
    end
end

function age_key
    need age-keygen
    umask 077
    if not test -f $age_key_file
        mkdir -p (path dirname $age_key_file)
        and chmod 700 (path dirname $age_key_file)
        and age-keygen -o $age_key_file 2>/dev/null
        or die "cannot create $age_key_file"
        say "created $age_key_file; it stays on this machine, back it up somewhere safe"
    end
    say "age public key of this node (give it to whoever runs secrets.fish init):"
    age-keygen -y $age_key_file
end

function new_ca -a name
    openssl ecparam -name prime256v1 -genkey -noout -out $ca_dir/$name.key
    and openssl req -x509 -new -key $ca_dir/$name.key -sha256 -days $ca_days -subj /CN=bbrf-$name \
        -out $ca_dir/$name.crt 2>/dev/null
    and cp $ca_dir/$name.crt $secrets_dir/$name.crt
    or die "cannot create the $name CA"
end

function new_node -a name ca addr
    openssl ecparam -name prime256v1 -genkey -noout -out $work/$name.key
    and openssl req -new -key $work/$name.key -subj /CN=bbrf-$name -out $work/$name.csr
    and printf '%s\n' \
        "subjectAltName="(san $addr) \
        extendedKeyUsage=serverAuth,clientAuth \
        basicConstraints=CA:FALSE \
        keyUsage=digitalSignature >$work/$name.ext
    and openssl x509 -req -in $work/$name.csr -CA $ca_dir/$ca.crt -CAkey $ca_dir/$ca.key \
        -CAserial $ca_dir/$ca.srl -CAcreateserial -sha256 -days $node_days \
        -extfile $work/$name.ext -out $secrets_dir/$name.crt 2>/dev/null
    or die "cannot issue the $name certificate"
end

function seal -a name node recipient
    begin
        echo "node: $node"
        echo "cookie: $cookie"
        echo "key: |"
        sed 's/^/  /' $work/$name.key
    end >$work/$name.yaml
    sops --encrypt --age $recipient,$admin_age --input-type yaml --output-type yaml \
        $work/$name.yaml >$secrets_dir/$name.enc.yaml
    or die "cannot encrypt $name.enc.yaml"
end

function init
    need openssl sops age-keygen

    ask HUB_ADDR "hub address (IP or hostname its distribution listens on)" '^[A-Za-z0-9.:-]+$'
    ask INGEST_ADDR "ingest node address" '^[A-Za-z0-9.:-]+$'
    ask HUB_AGE "hub age public key (run 'make age-key' on the hub)" '^age1[a-z0-9]+$'
    ask INGEST_AGE "ingest node age public key (run 'make age-key' on the ingest node)" '^age1[a-z0-9]+$'
    test $HUB_AGE != $INGEST_AGE; or die "the hub and the ingest node need their own age keys"

    set -l existing $secrets_dir/*.crt $secrets_dir/*.enc.yaml $ca_dir/*.key
    if set -q existing[1]
        printf '%s\n' $existing
        confirm "these files will be replaced, which invalidates the current deployment. go on?"
        or exit 1
    end

    mkdir -p $secrets_dir $ca_dir; and chmod 700 $ca_dir; or die "cannot create $secrets_dir and $ca_dir"
    set -l serials $ca_dir/*.srl
    rm -f $serials
    umask 077

    if not test -f $admin_age_key_file
        mkdir -p (path dirname $admin_age_key_file)
        and age-keygen -o $admin_age_key_file 2>/dev/null
        or die "cannot create $admin_age_key_file"
        say "created the admin age key $admin_age_key_file; back it up, it opens both node files"
    end
    set -g admin_age (age-keygen -y $admin_age_key_file); or die "cannot read $admin_age_key_file"

    # plaintext keys only ever live here, in memory where the system allows
    set -l tmp (env_or TMPDIR /tmp)
    test -w /dev/shm; and set tmp /dev/shm
    set -g work (mktemp -d $tmp/bbrf-secrets.XXXXXX); or die "cannot create a work directory in $tmp"
    function remove_work --on-event fish_exit
        rm -rf $work
    end
    function interrupted --on-signal INT --on-signal TERM
        exit 130
    end

    say "CAs: caI signs the ingest node, caH the hub, dud nothing (its key is thrown away)"
    new_ca caI
    new_ca caH
    new_ca dud
    rm -f $ca_dir/dud.key

    say "node certificates, $node_days days"
    new_node hub caH $HUB_ADDR
    new_node ingest caI $INGEST_ADDR

    set -g cookie (openssl rand -hex 32); or die "cannot generate the cookie"
    say "encrypting hub.enc.yaml (hub + admin) and ingest.enc.yaml (ingest + admin)"
    seal hub bbrf_hub@$HUB_ADDR $HUB_AGE
    seal ingest bbrf_ingest@$INGEST_ADDR $INGEST_AGE

    printf '%s\n' \
        '# each node file is readable by that node and the admin only' \
        'creation_rules:' \
        '  - path_regex: hub\.enc\.yaml$' \
        "    age: $HUB_AGE,$admin_age" \
        '  - path_regex: ingest\.enc\.yaml$' \
        "    age: $INGEST_AGE,$admin_age" >$secrets_dir/.sops.yaml
    chmod 644 $secrets_dir/*.crt $secrets_dir/*.enc.yaml $secrets_dir/.sops.yaml

    check

    printf '%s\n' \
        '' \
        "Done. Node names: bbrf_hub@$HUB_ADDR and bbrf_ingest@$INGEST_ADDR" \
        '' \
        "- $secrets_dir/ holds only public certificates and encrypted files; copy it to the other node" \
        '  (scp -r). It is gitignored: it belongs to this deployment, not to the project.' \
        "- $ca_dir holds the CA private keys. Move them offline (an encrypted drive or a password" \
        '  manager); they are needed only to issue new certificates.' \
        "- Back up the admin age key $admin_age_key_file."
end

function ok
    echo "  ok    $argv"
end

function bad
    echo "  FAIL  $argv"
    set -g failed 1
end

function enddate -a cert
    openssl x509 -enddate -noout -in $cert | string replace -r '^[^=]*=' ''
end

function check
    need openssl sops
    set -g failed 0

    say "checking $secrets_dir"
    for pair in hub:caH ingest:caI
        set -l name (string split -f1 : $pair)
        set -l ca (string split -f2 : $pair)
        set -l other caH
        test $ca = caH; and set other caI
        set -l cert $secrets_dir/$name.crt
        set -l enc $secrets_dir/$name.enc.yaml

        if openssl verify -CAfile $secrets_dir/$ca.crt $cert >/dev/null 2>&1
            ok "$name.crt is signed by $ca"
        else
            bad "$name.crt is not signed by $ca"
        end
        if openssl verify -CAfile $secrets_dir/$other.crt $cert >/dev/null 2>&1
            bad "$name.crt is also accepted by $other"
        end
        if openssl x509 -checkend (math '30 * 86400') -noout -in $cert >/dev/null
            ok "$name.crt expires "(enddate $cert)
        else
            bad "$name.crt expires within 30 days: "(enddate $cert)
        end
        if grep -q "PRIVATE KEY" $enc
            bad "$name.enc.yaml contains a plaintext private key"
        else
            ok "$name.enc.yaml holds no plaintext key"
        end
        if test -f $admin_age_key_file
            set -l cert_pub (openssl x509 -pubkey -noout -in $cert | string collect)
            set -l key_pub (SOPS_AGE_KEY_FILE=$admin_age_key_file sops --decrypt --extract '["key"]' $enc |
                openssl pkey -pubout 2>/dev/null | string collect)
            if test -n "$key_pub" -a "$cert_pub" = "$key_pub"
                ok "$name.enc.yaml decrypts with the admin key and its key matches $name.crt"
            else
                bad "$name.enc.yaml does not decrypt with the admin key, or its key does not match $name.crt"
            end
        end
    end
    test $failed = 0; or die "check failed"
end

switch "$argv[1]"
    case age-key
        age_key
    case init
        init
    case check
        check
    case '*'
        sed -n '2,11p' (status filename) | sed 's/^# \{0,1\}//'
        exit 1
end

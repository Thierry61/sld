# List of repositories to analyze
declare -A repos
repos=([safe_browser]=master [safe_nodejs]=master [safe-api]=master [safe_client_libs]=master [quic-p2p]=master [safe_vault]=master [routing]=fleming
[safe-nd]=master [self_encryption]=master [parsec]=master)

# Output file
dot=db.dot

# toml path
toml=toml-cli/target/debug/toml

# Dot file header
cat > $dot <<END_OF_HEADER
digraph g {
  stylesheet = "./db.css"
  graph[
    rankdir = "LR"
    splines = "polyline"
  ];
  node[
    fontsize = "14"
    margin = 0.15
    fontname = "verdana"
    shape = "record"
  ];
  edge[
    minlen=3
    color="DarkGreen"
    arrowhead="vee"
    arrowsize=0.5
  ];
END_OF_HEADER

# Download and build toml-cli if not already done
if [ ! -f "$toml" ]
then
    rm -rf toml-cli
    git clone https://github.com/gnprice/toml-cli
    cd toml-cli
    cargo build
    cd ..
fi

declare -A repos_in_workspace
declare -A repos_dependencies

# Generate links
function analyze_dependencies () {
    dependencies=${repos_dependencies[$repo]}
    if [ $dependencies ]
    then
        for dependency in $(echo $dependencies | jq -r 'keys[]')
        do
            src_workspace=${repos_in_workspace[$repo]}
            dst_workspace=${repos_in_workspace[$dependency]}
            # Only links to listed repositories
            if [ $dst_workspace ] || [ ${repos[$dependency]} ]
            then
                if [ $src_workspace ]
                then
                    printf "\"$src_workspace\":\"K_$repo\"" >> $dot
                else
                    printf "\"$repo\"" >> $dot
                fi
                printf " -> " >> $dot
                if [ $dst_workspace ]
                then
                    printf "\"$dst_workspace\":\"K_$dependency\"" >> $dot
                else
                    printf "\"$dependency\"" >> $dot
                fi
                if [ $src_workspace ] && [ $dst_workspace ] && [ $src_workspace == $dst_workspace ]
                then
                    printf "\t[color=\"grey\"]" >> $dot
                fi
                printf "\n" >> $dot
            fi
        done
    fi
}

for repo in "${!repos[@]}"
do
    # No root key for safe-api (because it is both a root crate and a sub-crate)
    if [ $repo == "safe-api" ]
    then
        root_key=""
    else
        root_key="<K_$repo> "
    fi
    printf "\n\"$repo\" [\n  label = \"$root_key\\N" >> $dot
    # Special cases for npm repos
    if [ $repo == "safe_browser" ]
    then
        echo "Special case $repo"
        repos_dependencies[$repo]="{\"native\":1}"
    elif [ $repo == "safe_nodejs" ]
    then
        echo "Special case $repo"
        printf "|<K_native> native" >> $dot
        repos_dependencies["native"]="{\"safe-api\":1}"
        repos_in_workspace["native"]=$repo
    else
        echo "Analyzing $repo"
        curl -s "https://raw.githubusercontent.com/maidsafe/$repo/${repos[$repo]}/Cargo.toml" > Cargo.toml
        dependencies=$($toml get Cargo.toml dependencies)
        if [ $dependencies != null ]
        then
            # Regular Rust repo
            repos_dependencies[$repo]=$dependencies
        else
            # Rust repo with workspaces
            for subdir in $($toml get Cargo.toml workspace.members | jq -r '.[]')
            do
                # Skip test subcrate
                if [ $subdir != "tests" ]
                then
                    repos_in_workspace[$subdir]=$repo
                    printf "|<K_$subdir> $subdir" >> $dot
                    curl -s "https://raw.githubusercontent.com/maidsafe/$repo/${repos[$repo]}/$subdir/Cargo.toml" > Cargo.toml
                    repos_dependencies[$subdir]=$($toml get Cargo.toml dependencies)
                fi
            done
        fi
        rm Cargo.toml
    fi
    printf "\"\n]\n" >> $dot
done

printf "\n" >> $dot

for repo in "${!repos_dependencies[@]}"
do
    analyze_dependencies
done

# Dot file trailer
echo "}" >> $dot

# Generate svg file from fot file
dot -T svg -o db.svg db.dot

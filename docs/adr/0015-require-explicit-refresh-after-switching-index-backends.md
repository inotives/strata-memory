# Require explicit refresh after switching index backends

After `index.backend` changes, `strata refresh` or `strata db-migrate` may create the selected backend's database, but search and status commands will not rebuild it implicitly. If the selected index is missing, commands fail with guidance to run `strata refresh`, preserving Strata's explicit search-freshness contract.

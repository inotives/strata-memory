# Test refresh recovery by rerunning the rebuild

Backend recovery tests will interrupt `strata refresh` during writes and then rerun it against the synthetic fixture. Strata does not promise that the interrupted partial refresh remains queryable, but the rerun must complete successfully and produce a valid complete index without manual database repair for both SQLite and Turso.

#!/bin/bash
# Runs every database constraint suite on PostgreSQL 16 (needs a local postgres and the 'postgres' OS user: adapt `su postgres -c` if needed).
# usage: ./run_db_tests.sh   (from the db_tests folder; migrations are read from ../migrations)
HERE="$(cd "$(dirname "$0")" && pwd)"; M="$HERE/../../backend/src/main/resources/db/migration"
mig(){ ls $M/V$1__*.sql; }
pg_isready -q || { service postgresql start >/dev/null 2>&1; for i in 1 2 3 4 5 6 7 8; do pg_isready -q && break; sleep 1; done; }
chk(){ python3 - "$1" "$2" << 'PY'
import sys
cases=[]
for l in open(sys.argv[1]).read().splitlines():
    if l.startswith('--- '): cases.append([l,False,''])
    elif l.startswith('ERROR') and cases and not cases[-1][1]: cases[-1][1]=True; cases[-1][2]=l[:140]
ok=0
for h,e,m in cases:
    good = e if 'FAIL expected' in h else not e; ok+=good
    if not good: print("  MISMATCH:",h[:90],"->",m or "no error")
print(f"{sys.argv[2]}: {len(cases)} cases, {ok} as expected")
PY
}
# build <db> <fixture-after-V007 or -> <last migration number> ; then run each given file (setup files apply, t*.sql are checked)
suite(){ db=$1; fx=$2; last=$3; shift 3
  su postgres -c "psql -q -c 'DROP DATABASE IF EXISTS $db'" 2>&1 | grep -v NOTICE; su postgres -c "psql -q -c 'CREATE DATABASE $db'"
  ap(){ su postgres -c "psql -v ON_ERROR_STOP=1 -q -d $db" < "$1" >/dev/null 2>/tmp/e_$db.txt || { echo "FAIL $1"; head -2 /tmp/e_$db.txt; }; }
  for n in 1 2 3 4 5 6 7; do ap $(mig $(printf %03d $n)); done
  [ "$fx" != "-" ] && ap "$HERE/$fx"
  for n in $(seq 8 $last); do ap $(mig $(printf %03d $n)); done
  for f in "$@"; do case $f in t0*|t_*|core_*) su postgres -c "psql -d $db" < "$HERE/$f" > "$HERE/out_$db.txt" 2>&1; chk "$HERE/out_$db.txt" "$f";; *) ap "$HERE/$f";; esac; done; }
suite dt_core   - 16 core_t.sql
suite dt_p2     fixture_two_outlets.sql 16 t_part2_t010.sql t011.sql
suite dt_a      - 16 setup012.sql t012.sql
suite dt_b      fixture_two_outlets.sql 16 setup013.sql setup013_devices.sql t013.sql
suite dt_c      setup014.sql 16 c_fixture_t014.sql t014.sql
suite dt_d      - 16 t015.sql
suite dt_v16    fixture_two_outlets.sql 16 t016.sql
suite dt_v17    fixture_two_outlets.sql 17 setup017.sql t017.sql
suite dt_rep    reports_base.sql        17 reg_base.sql reports_fx.sql
GALLA_DB=dt_rep python3 "$HERE/run_reports_test.py" | tail -1
su postgres -c "psql -d dt_v17 -Atc \"select 'tables after V001-V017: '||count(*) from information_schema.tables where table_schema='public'\""

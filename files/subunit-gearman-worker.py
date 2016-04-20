#!/usr/bin/python2
#
# Copyright 2013 Hewlett-Packard Development Company, L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import argparse
import daemon
import gear
import gzip
import io
import json
import logging
import os
import socket
import time
import urllib2
import yaml

from subunit2sql import read_subunit
from subunit2sql import shell


try:
    import daemon.pidlockfile as pidfile_mod
except ImportError:
    import daemon.pidfile as pidfile_mod


def semi_busy_wait(seconds):
    # time.sleep() may return early. If it does sleep() again and repeat
    # until at least the number of seconds specified has elapsed.
    start_time = time.time()
    while True:
        time.sleep(seconds)
        cur_time = time.time()
        seconds = seconds - (cur_time - start_time)
        if seconds <= 0.0:
            return


class FilterException(Exception):
    pass


class SubunitRetriever(object):
    def __init__(self, gearman_worker, filters, subunit2sql_conf):
        super(SubunitRetriever, self).__init__()
        self.gearman_worker = gearman_worker
        self.filters = filters
        # Initialize subunit2sql settings
        self.config = subunit2sql_conf
        shell.cli_opts()
        extensions = shell.get_extensions()
        shell.parse_args([], [self.config])
        self.extra_targets = shell.get_targets(extensions)

    def _write_to_db(self, subunit):
        subunit_v2 = subunit.pop('subunit')
        # Set run metadata from gearman
        log_url = subunit.pop('log_url', None)
        if log_url:
            log_dir = os.path.dirname(log_url)

            # log_dir should be the top-level directory containing a job run,
            # but the subunit file may be nested in 0 - 2 subdirectories (top,
            # logs/, or logs/old/), so we need to safely correct the path here
            log_base = os.path.basename(log_dir)
            if log_base == 'logs':
                log_dir = os.path.dirname(log_dir)
            elif log_base == 'old':
                log_dir = os.path.dirname(os.path.dirname(log_dir))

            shell.CONF.set_override('artifacts', log_dir)
        shell.CONF.set_override('run_meta', subunit)
        # Parse subunit stream and store in DB
        if subunit_v2.closed:
            logging.debug('Trying to convert closed subunit v2 stream: %s to '
                          'SQL' % subunit_v2)
        else:
            logging.debug('Converting Subunit V2 stream: %s to SQL' %
                          subunit_v2)
        stream = read_subunit.ReadSubunit(subunit_v2,
                                          targets=self.extra_targets)
        results = stream.get_results()
        start_time = sorted(
            [results[x]['start_time'] for x in results if x != 'run_time'])[0]
        shell.CONF.set_override('run_at', start_time.isoformat())
        shell.process_results(results)
        subunit_v2.close()

    def run(self):
        while True:
            try:
                self._handle_event()
            except:
                logging.exception("Exception retrieving log event.")

    def _handle_event(self):
        job = self.gearman_worker.getJob()
        try:
            arguments = json.loads(job.arguments.decode('utf-8'))
            source_url = arguments['source_url']
            retry = arguments['retry']
            event = arguments['event']
            logging.debug("Handling event: " + json.dumps(event))
            fields = event.get('fields') or event.get('@fields')
            if fields.pop('build_status') != 'ABORTED':
                # Handle events ignoring aborted builds. These builds are
                # discarded by zuul.
                subunit_io = self._retrieve_subunit_v2(source_url, retry)
                if not subunit_io:
                    raise Exception('Unable to retrieve subunit stream')
                else:
                    if subunit_io.closed:
                        logging.debug("Pushing closed subunit file: %s" %
                                      subunit_io)
                    else:
                        logging.debug("Pushing subunit file: %s" % subunit_io)
                    out_event = fields.copy()
                    out_event["subunit"] = subunit_io
                    self._write_to_db(out_event)
            job.sendWorkComplete()
        except Exception as e:
            logging.exception("Exception handling log event.")
            job.sendWorkException(str(e).encode('utf-8'))

    def _retrieve_subunit_v2(self, source_url, retry):
        # TODO (clarkb): This should check the content type instead of file
        # extension for determining if gzip was used.
        gzipped = False
        raw_buf = b''
        try:
            gzipped, raw_buf = self._get_subunit_data(source_url, retry)
        except urllib2.HTTPError as e:
            if e.code == 404:
                logging.info("Unable to retrieve %s: HTTP error 404" %
                             source_url)
            else:
                logging.exception("Unable to get log data.")
            return None
        except Exception:
            # Silently drop fatal errors when retrieving logs.
            # TODO (clarkb): Handle these errors.
            # Perhaps simply add a log message to raw_buf?
            logging.exception("Unable to get log data.")
            return None
        if gzipped:
            logging.debug("Decompressing gzipped source file.")
            raw_strIO = io.BytesIO(raw_buf)
            f = gzip.GzipFile(fileobj=raw_strIO)
            buf = io.BytesIO(f.read())
            raw_strIO.close()
            f.close()
        else:
            logging.debug("Decoding source file.")
            buf = io.BytesIO(raw_buf)
        return buf

    def _get_subunit_data(self, source_url, retry):
        gzipped = False
        try:
            # TODO(clarkb): We really should be using requests instead
            # of urllib2. urllib2 will automatically perform a POST
            # instead of a GET if we provide urlencoded data to urlopen
            # but we need to do a GET. The parameters are currently
            # hardcoded so this should be ok for now.
            logging.debug("Retrieving: " + source_url + ".gz")
            req = urllib2.Request(source_url + ".gz")
            req.add_header('Accept-encoding', 'gzip')
            r = urllib2.urlopen(req)
        except urllib2.URLError:
            try:
                # Fallback on GETting unzipped data.
                logging.debug("Retrieving: " + source_url)
                r = urllib2.urlopen(source_url)
            except:
                logging.exception("Unable to retrieve source file.")
                raise
        except:
            logging.exception("Unable to retrieve source file.")
            raise
        if ('gzip' in r.info().get('Content-Type', '') or
            'gzip' in r.info().get('Content-Encoding', '')):
            gzipped = True

        raw_buf = r.read()
        # Hack to read all of Jenkins console logs as they upload
        return gzipped, raw_buf


class Server(object):
    def __init__(self, config, debuglog):
        # Config init.
        self.config = config
        self.gearman_host = self.config['gearman-host']
        self.gearman_port = self.config['gearman-port']
        # Pythong logging output file.
        self.debuglog = debuglog
        self.retriever = None
        self.filter_factories = []

    def setup_logging(self):
        if self.debuglog:
            logging.basicConfig(format='%(asctime)s %(message)s',
                                filename=self.debuglog, level=logging.DEBUG)
        else:
            # Prevent leakage into the logstash log stream.
            logging.basicConfig(level=logging.CRITICAL)
        logging.debug("Log pusher starting.")

    def setup_retriever(self):
        hostname = socket.gethostname()
        gearman_worker = gear.Worker(hostname + b'-pusher')
        gearman_worker.addServer(self.gearman_host,
                                 self.gearman_port)
        gearman_worker.registerFunction(b'push-subunit')
        subunit2sql_conf = self.config['config']
        self.retriever = SubunitRetriever(gearman_worker,
                                          self.filter_factories,
                                          subunit2sql_conf)

    def main(self):
        self.setup_retriever()
        self.retriever.run()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-c", "--config", required=True,
                        help="Path to yaml config file.")
    parser.add_argument("-d", "--debuglog",
                        help="Enable debug log. "
                             "Specifies file to write log to.")
    parser.add_argument("--foreground", action='store_true',
                        help="Run in the foreground.")
    parser.add_argument("-p", "--pidfile",
                        default="/var/run/jenkins-subunit-pusher/"
                                "jenkins-subunit-gearman-worker.pid",
                        help="PID file to lock during daemonization.")
    args = parser.parse_args()

    with open(args.config, 'r') as config_stream:
        config = yaml.load(config_stream)
    server = Server(config, args.debuglog)

    if args.foreground:
        server.setup_logging()
        server.main()
    else:
        pidfile = pidfile_mod.TimeoutPIDLockFile(args.pidfile, 10)
        with daemon.DaemonContext(pidfile=pidfile):
            server.setup_logging()
            server.main()


if __name__ == '__main__':
    main()

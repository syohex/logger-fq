#define _REENTRANT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "fq.h"

struct logger_fq_struct {
  fq_client client;
  char *host;
  int port;
  char *user;
  char *password;
  char *exchange;
  int heartbeat;
  int backlog;
  int connected;
};
typedef struct logger_fq_struct * Logger__Fq;

#define GLOBAL_LOGGER_FQS_MAX 16
static int GLOBAL_LOGGER_FQS_CNT = 0;
static Logger__Fq GLOBAL_LOGGER_FQS[GLOBAL_LOGGER_FQS_MAX];

#define int_from_hv(hv,name) \
 do { SV **v; if(NULL != (v = hv_fetch(hv, #name, strlen(#name), 0))) name = SvIV(*v); } while(0)
#define double_from_hv(hv,name) \
 do { SV **v; if(NULL != (v = hv_fetch(hv, #name, strlen(#name), 0))) name = SvNV(*v); } while(0)
#define str_from_hv(hv,name) \
 do { SV **v; if(NULL != (v = hv_fetch(hv, #name, strlen(#name), 0))) name = SvPV_nolen(*v); } while(0)

MODULE = Logger::Fq PACKAGE = Logger::Fq PREFIX = logger_fq_

REQUIRE:        1.9505
PROTOTYPES:     DISABLE

Logger::Fq
logger_fq_new(clazz, ...)
  char *clazz
  PREINIT:
    HV *options;
    char *user = "guest";
    char *password = "guest";
    char *host = "127.0.0.1";
    int port = 8765;
    double heartbeat = 1.0;
    int backlog = 10000;
    char *exchange = "logging";
  CODE:
    Logger__Fq logger;
    if(GLOBAL_LOGGER_FQS_CNT >= GLOBAL_LOGGER_FQS_MAX) {
      Perl_croak(aTHX_ "Too many Logger::Fq instances...");
    }
    logger = calloc(1, sizeof(*logger));
    GLOBAL_LOGGER_FQS[GLOBAL_LOGGER_FQS_CNT++] = logger;
    if(items > 1) {
      if(SvTYPE(SvRV(ST(1))) == SVt_PVHV) {
        options = (HV*)SvRV(ST(1));
        str_from_hv(options, user);
        str_from_hv(options, password);
        str_from_hv(options, host);
        str_from_hv(options, exchange);
        int_from_hv(options, port);
        int_from_hv(options, backlog);
        double_from_hv(options, heartbeat);
      } else {
        Perl_croak(aTHX_ "optional parameter to Logger::Fq->new must be hashref");
      }
    }

    logger->user = strdup(user);
    logger->password = strdup(password);
    logger->host = strdup(host);
    logger->exchange = strdup(exchange);
    logger->port = port;
    logger->backlog = backlog;
    logger->heartbeat = (int)(heartbeat * 1000.0);
    fq_client_init(&logger->client, 0, NULL);
    fq_client_creds(logger->client, logger->host, logger->port,
                    logger->user, logger->password);
    fq_client_heartbeat(logger->client, logger->heartbeat);
    fq_client_set_backlog(logger->client, logger->backlog, 0);
    fq_client_set_nonblock(logger->client, 1);
    RETVAL = logger;
  OUTPUT:
    RETVAL

int
logger_fq_log(logger, routing_key, body, ...)
  Logger::Fq logger
  char *routing_key
  SV *body
  PREINIT:
    fq_msg *msg;
    STRLEN len;
    void *body_buf;
    char *exchange;
    int rv;
  CODE:
    if(!logger->connected) {
      logger->connected = 1;
      fq_client_connect(logger->client);
    }
    body_buf = SvPV(body, len);
    msg = fq_msg_alloc(body_buf, len);
    fq_msg_id(msg, NULL);
    exchange = logger->exchange;
    if(items > 3) {
      exchange = SvPV_nolen(ST(3));
    }
    fq_msg_exchange(msg, exchange, strlen(exchange));
    fq_msg_route(msg, routing_key, strlen(routing_key));
    rv = fq_client_publish(logger->client, msg);
    fq_msg_free(msg);
    RETVAL = rv;
  OUTPUT:
    RETVAL

int
logger_fq_backlog()
  PREINIT:
    int msgs = 0;
    int i;
  CODE:
    for(i=0; i<GLOBAL_LOGGER_FQS_CNT; i++)
      msgs += fq_client_data_backlog(GLOBAL_LOGGER_FQS[i]->client);
    RETVAL = msgs;
  OUTPUT:
    RETVAL

int
logger_fq_drain(timeout_ms)
  int timeout_ms
  PREINIT:
    int msgs;
    int initial = 0;
    int i;
  CODE:
    while(timeout_ms > 0) {
      msgs = 0;
      for(i=0; i<GLOBAL_LOGGER_FQS_CNT; i++)
        msgs += fq_client_data_backlog(GLOBAL_LOGGER_FQS[i]->client);
      if(!initial) initial = msgs;
      if(msgs == 0) break;
      usleep(MIN(timeout_ms, 10000));
      timeout_ms -= 10000;
    }
    RETVAL = (initial - msgs);
  OUTPUT:
    RETVAL
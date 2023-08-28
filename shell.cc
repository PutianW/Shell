#include <cstdio>
#include <unistd.h>
#include <iostream>
#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <stdlib.h>
#include <sys/wait.h>

#include "shell.hh"

int yyparse(void);
extern void shellrc();
bool iskill = false;

void Shell::prompt() {
  if (isatty(0) && !_source && !iskill) {
    printf("myshell>");
    fflush(stdout);
  }
  if (iskill) {
    iskill = false;
  }
}

void disp(int sig) {
  if (sig == SIGINT) {
    iskill = true;
	  printf("\n");
    printf("myshell>");
    fflush(stdout);
  }
}

void disp_zombie(int sig) {
  if (sig == SIGCHLD) {
	  while (waitpid(-1, NULL, WNOHANG) > 0) {
    }
  }
}

int main() {
  struct sigaction sa;
  sa.sa_handler = disp;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART;

  struct sigaction sa_zombie;
  sa_zombie.sa_handler = disp_zombie;
  sigemptyset(&sa_zombie.sa_mask);
  sa_zombie.sa_flags = SA_RESTART;

  if(sigaction(SIGINT, &sa, NULL)){
      perror("sigaction");
      exit(2);
  }
  
  if(sigaction(SIGCHLD, &sa_zombie, NULL)){
      perror("sigaction");
      exit(2);
  }


  // shell.rc
  shellrc();

  // print prompt
  Shell::prompt();

  // start reading buffer
  yyparse();
}

Command Shell::_currentCommand;
bool Shell::_source;
extern void shellrc();
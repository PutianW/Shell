
/*
 *
 * CS-252 
 * shell.l: lexical analyzer for shell
 * You have to extend it.
 *
 */

%{

#include <cstring>
#include "y.tab.hh"
#include "shell.hh"
#include <string>
#include <unistd.h>



extern "C" char * read_line();

int mygetc(FILE * f) {
  static char *p;
  char ch;

     if (!isatty(0)) {
  // stdin is not a tty. Call real getc
    return getc(f);
  }

  // stdin is a tty. Call our read_line.
  if (p==NULL || *p == 0) {
    char * s = read_line();
    p = s;
  }

  ch = *p;
  p++;

  return ch;
}

#undef getc
#define getc(f) mygetc(f)




static void yyunput (int c,char *buf_ptr  );

char * goodbye_message = (char *) "\n  Good bye!!\n\n";

void myunputc(int c) {
  unput(c);
}

void source(FILE * file) {
  // set the source detect bool to TRUE
  Shell::_source = true;
  YY_BUFFER_STATE old = YY_CURRENT_BUFFER;
  YY_BUFFER_STATE buffer = yy_create_buffer(file, YY_BUF_SIZE);
  yypush_buffer_state(buffer);
  yyparse();
  yy_switch_to_buffer(old);
  // set the source detect bool to FALSE
  Shell::_source = false;
  Shell::prompt();
}

void shellrc() {
  FILE * shellrc = fopen(".shellrc", "r");
  if (shellrc) {
    Shell::_source = true;
    // set shellrc as input buffer
    yyrestart(shellrc);
    // start executing the commands in shellrc
    yyparse();
    // restart the input buffer back to stdin
    yyrestart(stdin);
    fclose(shellrc);
    Shell::_source = false;
  }
}

%}

%option noyywrap

%%

"\n" {
  return NEWLINE;
}

[ \t] {
  /* Discard spaces and tabs */
}

"|" {
  return PIPE;
}

">" {
  return GREAT;
}

"<" {
  return LESS;
}

"&" {
  return AMPERSAND;
}

">&" {
  return GREATAMPERSAND;
}

">>" {
  return GREATGREAT;
}

">>&" {
  return GREATGREATAMPERSAND;
}

"2>" {
  return TWOGREAT;
}

"exit" {
  return EXIT;
}


[^ \n\t(\$\{)]*\$\{[^ \t\n][^ \t\n]*\}[^ \t\n]*  {
  std::string s = std::string(yytext);

  int i = 0;
  int j = 0;
  for (i; i < s.length(); i++) {
    if (s.at(i) == '$') {
      break;
    }
  }

  for (j = i; j < s.length(); j++) {
    if (s.at(j) == '}') {
      break;
    }
  }

  int start = i + 2;
  int size = j - i - 2;

  if (s.substr(start, size) == "$") {
    // get pid
    s = s.substr(0, i) + std::to_string(getpid()) + s.substr(j + 1);

  } else if (s.substr(start, size) == "?") {
    // get the last return code
    s = s.substr(0, i) + std::to_string(Shell::_currentCommand._last_return_code) + s.substr(j + 1);

  } else if (s.substr(start, size) == "!") {
    // get the last PID of child process
    s = s.substr(0, i) + std::to_string(Shell::_currentCommand._last_PID) + s.substr(j + 1);

  } else if (s.substr(start, size) == "_") {
    // get the last argument in the fully expanded previous command
    s = s.substr(0, i) + Shell::_currentCommand.getLastArg() + s.substr(j + 1);

  } else if (s.substr(start, size) == "SHELL") {
    // get the path of the shell executable
    char path[1024];
    realpath("../shell", path);
    s = s.substr(0, i) + std::string(path) + s.substr(j + 1);

  } else {
    
    // get the value of environment variable
    if (getenv((s.substr(start, size)).c_str())) {
      s = s.substr(0, i) + std::string(getenv((s.substr(start, size)).c_str())) + s.substr(j + 1);
    } else {
      fprintf(stderr, "getenv: error\n");
      yyparse();
    }

  }

  // push back into lex's input buffer
  for (int x = s.length() - 1; x >= 0; x--) {
      myunputc(s.at(x));
  }

}


\$\([^\n]*\)  {
  std::string subCommands = std::string(yytext);

  // get rid of "$(" and ")" characters
  subCommands = subCommands.substr(2, subCommands.length() - 3);
  
  // initialize input pipe of the subshell
  int pipeIn[2];
  pipe(pipeIn);

  // initialize output pipe of the subshell
  int pipeOut[2];
  pipe(pipeOut);

  // store the standard-in and standard-out for this shell
  int tempin = dup(0);
  int tempout = dup(1);

  // redirect the input of shell to the pipeIn buffer output
  dup2(pipeIn[0], 0);

  // redirect the output of shell to the pipeOut buffer input.
  dup2(pipeOut[1], 1);

  // close the pointing of pipes
  close(pipeIn[0]);
  close(pipeOut[1]);

  // write the commands into the pipeIn buffer input, including the "exit" command
  write(pipeIn[1], subCommands.c_str(), subCommands.length());
  write(pipeIn[1], "\n", 1);
  write(pipeIn[1], "exit\n", 5);
  close(pipeIn[1]);

  // start child process to run subshell
  int ret = fork();

  if (ret == 0) {
    // child process, start subshell
    // create argument array that runs the shell itself in child process
    char ** args = new char *[2];
    args[0] = (char *) "/proc/self/exe";
    args[1] = NULL;
    execvp(args[0], args);

    // error handler
    perror("execvp");
    exit(1);

  } else if (ret < 0) {
    // print error if fork() failed
    perror("subshell: fork");
    exit(1);
  }

  // restore the standard-in and standard-out
  dup2(tempin, 0);
  dup2(tempout, 1);
  close(tempin);
  close(tempout);

  // create a buffer to store the output buffer from subshell, which is the output of pipeOut buffer
  char * pipeOut_buffer = new char[4096];
  int i = 0;
  char c;

  // read every character from the output buffer into the newly created buffer
  while (read(pipeOut[0], &c, 1)) {
    if (c == '\n') {
      // convert each newline character to space
      pipeOut_buffer[i] = ' ';
    } else {
      pipeOut_buffer[i] = c;
    }
    i++;
  }

  // add an EOF character to the end of the buffer
  pipeOut_buffer[i] = '\0';
  close(pipeOut[0]);

  // append the content of this buffer to the lex input buffer in the reversed order
  // remove the goodbye message of the "exit" command
  i = strlen(pipeOut_buffer) - strlen(goodbye_message);
  for (i; i >= 0; i--) {
    myunputc(pipeOut_buffer[i]);
  }

  // free the used buffer
  free(pipeOut_buffer);
}


[~][^ \n\t]* {
  yylval.cpp_string = new std::string(yytext);
  if (yylval.cpp_string->length() == 1) {
    yylval.cpp_string = new std::string(getenv("HOME"));
  } else {
    *yylval.cpp_string = "/homes/" + yylval.cpp_string->substr(1, yylval.cpp_string->length() - 1);
  }
  return WORD;
}


["][^\t]*["]  {
  /* Assume that file names have only alpha chars */
  yylval.cpp_string = new std::string(yytext);
  *yylval.cpp_string = yylval.cpp_string->substr(1, yylval.cpp_string->length() - 2);
  int size = yylval.cpp_string->length();
  for (int i = 0; i < size; i++) {
    if (yylval.cpp_string->at(i) == '\\') {
      yylval.cpp_string->replace(i, 1, "");
      size--;
    }
  }
  return WORD;
}

([^ \n|\\%&<>"]*\\[^ \t\n]?)([^ \n|\\%&<>"]*\\[^ \t\n]?)*[^ \t\n|<>]*  {
  /* Assume that file names have only alpha chars */
  yylval.cpp_string = new std::string(yytext);
  int size = yylval.cpp_string->length();
  for (int i = 0; i < size; i++) {
    if (yylval.cpp_string->at(i) == '\\') {
      yylval.cpp_string->replace(i, 1, "");
      size--;
    }
  }
  return WORD;
}

[^ \t\n|<>&][^ \t\n|<>&]*  {
  /* Assume that file names have only alpha chars */
  yylval.cpp_string = new std::string(yytext);
  return WORD;
}

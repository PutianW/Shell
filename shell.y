
/*
 * CS-252
 * shell.y: parser for shell
 *
 * This parser compiles the following grammar:
 *
 *	cmd [arg]* [> filename]
 *
 * you must extend it to understand the complete shell grammar
 *
 */

%code requires 
{
#include <string>

#if __cplusplus > 199711L
#define register      // Deprecated in C++11 so remove the keyword
#endif
}

%union
{
  char        *string_val;
  // Example of using a c++ type in yacc
  std::string *cpp_string;
}

%token <cpp_string> WORD
%token NOTOKEN GREAT NEWLINE PIPE LESS AMPERSAND GREATAMPERSAND GREATGREAT GREATGREATAMPERSAND TWOGREAT EXIT

%{
//#define yylex yylex
#include <cstdio>
#include <sys/types.h>
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <cassert>
#include "shell.hh"

#define MAXFILENAME 1024

void expandWildcardsIfNecessary(std::string * strArg);
void expandWildcard(char * prefix, char * suffix);
int cmpfunc(const void *a, const void *b);
extern char * goodbye_message;
void yyerror(const char * s);
int yylex();

%}


%%

goal:
  commands
  ;

commands:
  command
  | commands command
  ;

command: simple_command
       ;

simple_command:	
  pipe_list iomodifier_list background_opt NEWLINE {
    /*printf("   Yacc: Execute command\n");*/
    Shell::_currentCommand.execute();
  }
  | NEWLINE {
    Shell::prompt();
  }
  | EXIT {
    printf("%s", goodbye_message);
    Shell::_currentCommand.clear();
    exit(0);
  }
  | error NEWLINE { yyerrok; }
  ;

command_and_args:
  command_word argument_list {
    Shell::_currentCommand.insertSimpleCommand( Command::_currentSimpleCommand );
  }
  ;

argument_list:
  argument_list argument
  | /* can be empty */
  ;

argument:
  WORD {
    /*printf("   Yacc: insert argument \"%s\"\n", $1->c_str());*/
    expandWildcardsIfNecessary( $1 );
  }
  ;

command_word:
  WORD {
    /*printf("   Yacc: insert command \"%s\"\n", $1->c_str());*/
    Command::_currentSimpleCommand = new SimpleCommand();
    Command::_currentSimpleCommand->insertArgument( $1 );
  }
  ;

pipe_list:
  command_and_args
  | pipe_list PIPE command_and_args
  ;

background_opt:
  AMPERSAND {
    /*printf("   Yacc: add background \n");*/
    Shell::_currentCommand._background = true;
  }
  | /* empty */
  ;

iomodifier_list:
  iomodifier_list iomodifier_opt
  | /* empty */
  ;


iomodifier_opt:
  GREAT WORD {
    if ( Shell::_currentCommand._outFile ) {
      Shell::_currentCommand._redirect_err = true;
      printf("Ambiguous output redirect.\n");
    }
    Shell::_currentCommand._outFile = $2;
  }
  | GREATGREAT WORD {
    if ( Shell::_currentCommand._outFile ) {
      Shell::_currentCommand._redirect_err = true;
      printf("Ambiguous output redirect.\n");
    }
    Shell::_currentCommand._append = true;
    Shell::_currentCommand._outFile = $2;
  }
  | GREATGREATAMPERSAND WORD {
    if ( Shell::_currentCommand._outFile || Shell::_currentCommand._errFile ) {
      Shell::_currentCommand._redirect_err = true;
      printf("Ambiguous output redirect.\n");
    }
    Shell::_currentCommand._append = true;
    Shell::_currentCommand._outFile = $2;
    Shell::_currentCommand._errFile = $2;
  }
  | GREATAMPERSAND WORD {
    if ( Shell::_currentCommand._outFile || Shell::_currentCommand._errFile ) {
      Shell::_currentCommand._redirect_err = true;
      printf("Ambiguous output redirect.\n");
    }
    Shell::_currentCommand._outFile = $2;
    Shell::_currentCommand._errFile = $2;
  }
  | LESS WORD {
    if ( Shell::_currentCommand._inFile ) {
      Shell::_currentCommand._redirect_err = true;
      printf("Ambiguous output redirect.\n");
    }
    Shell::_currentCommand._inFile = $2;
  }
  | TWOGREAT WORD {
    if ( Shell::_currentCommand._errFile ) {
      Shell::_currentCommand._redirect_err = true;
      printf("Ambiguous output redirect.\n");
    }
    Shell::_currentCommand._errFile = $2;
  }
  ;

%%

void yyerror(const char * s)
{
  fprintf(stderr,"%s", s);
}


int cmpfunc(const void *a, const void *b) {
  return strcmp( *(const char **) a, *(const char **) b);
}


int maxEntries;
int nEntries;
char ** array;
bool abs_path = false;

void expandWildcard(char * prefix, char * suffix) {
  if (suffix[0] == 0) {
    if (nEntries == maxEntries) {
      // reallocate array size if necessary
      maxEntries *= 2;
      array = (char **) realloc(array, maxEntries * sizeof(char *));
      assert(array != NULL);
    }
    array[nEntries] = strdup(prefix);
    nEntries++;
    return;
  }

  char * s = strchr(suffix + 1, '/');
  char component[MAXFILENAME];

  if (s != NULL) {
    if (abs_path) {
      strncpy(component, suffix + 1, s - suffix - 1);
    } else {
      strncpy(component, suffix, s - suffix);
    }
    suffix = s;
  } else {
    strcpy(component, suffix + 1);
    // let suffix points to the EOS character, which is 0
    suffix = suffix + strlen(suffix);
  }

  // printf("component: %s   prefix: %s    sufix: %s\n", component, prefix, suffix);

  char newPrefix[MAXFILENAME];
  if (strchr(component, '*') == NULL && strchr(component, '?') == NULL) {
    if (prefix == NULL) {
      if (abs_path) {
        sprintf(newPrefix, "/%s", component);
      } else {
        sprintf(newPrefix, "%s", component);
      }
    } else {
      sprintf(newPrefix, "%s/%s", prefix, component);
    }
    expandWildcard(newPrefix, suffix);
    return;
  }

  char * reg = (char *) malloc(2 * strlen(component) + 10);
  char * a = component;
	char * r = reg;
	*r = '^';
  r++;
  while (*a) {
		if (*a == '*') {
      *r = '.';
      r++;
      *r = '*';
      r++;
    } else if (*a == '?') {
      *r = '.';
      r++;
    } else if (*a == '.') {
      *r = '\\';
      r++;
      *r = '.';
      r++;
    } else {
      *r = *a;
      r++;
    }
		a++;
	}
  *r = '$';
  r++;
	*r = 0;

  // compile arg to regular expression object
  regex_t re;
  int result = regcomp(&re, reg, REG_EXTENDED | REG_NOSUB);
  if( result != 0 ) {
    fprintf(stderr, "Bad regular expresion\n");
    exit(-1);
  }

  // get directory pointer to the current directory
  char * directory;
  if (prefix == NULL) {
    if (abs_path) {
      directory = (char *) "/";
    } else {
      directory = (char *) ".";
    }
  } else {
    directory = prefix;
  }

  //printf("dir: %s\n", directory);

  DIR * dir = opendir(directory);
  // if this is a file not directory, then exists
	if (dir == NULL) {
    // printf("invalid dir: %s", directory);
		return;
	}

  // find the matching filenames
  struct dirent * ent;
  regmatch_t match;
  while ( (ent = readdir(dir)) != NULL) {
    if (regexec(&re, ent->d_name, 1, &match, 0) == 0) {
      // exclude the invisible files
      if (ent->d_name[0] == '.') {
        if (component[0] == '.') {
          if (prefix == NULL) {
            if (abs_path) {
              sprintf(newPrefix, "/%s", ent->d_name);
            } else {
              sprintf(newPrefix, "%s", ent->d_name);
            }
          } else {
            sprintf(newPrefix, "%s/%s", prefix, ent->d_name);
          }
          expandWildcard(newPrefix, suffix);
        }
      } else {
        if (prefix == NULL) {
          if (abs_path) {
            sprintf(newPrefix, "/%s", ent->d_name);
          } else {
            sprintf(newPrefix, "%s", ent->d_name);
          }
        } else {
          sprintf(newPrefix, "%s/%s", prefix, ent->d_name);
        }
        expandWildcard(newPrefix, suffix);
      }
    }
  }

  closedir(dir);
  regfree(&re);
	free(reg);

}


void expandWildcardsIfNecessary(std::string * strArg) {
  char * arg = (char *) strArg->c_str();
  if (strchr(arg, '*') == NULL && strchr(arg, '?') == NULL) {

    Command::_currentSimpleCommand->insertArgument(strArg);
    return;

  } else if (strchr(arg, '/') == NULL) {
    // without subdirectory
    char * reg = (char *) malloc(2 * strlen(arg) + 10);
    char * a = arg;
		char * r = reg;
		*r = '^';
    r++;
    while (*a) {
			if (*a == '*') {
        *r = '.';
        r++;
        *r = '*';
        r++;
      } else if (*a == '?') {
        *r = '.';
        r++;
      } else if (*a == '.') {
        *r = '\\';
        r++;
        *r = '.';
        r++;
      } else {
        *r = *a;
        r++;
      }
			a++;
		}
    *r = '$';
    r++;
		*r = 0;

    // compile arg to regular expression object
    regex_t re;
    int result = regcomp(&re, reg, REG_EXTENDED | REG_NOSUB);
    if( result != 0 ) {
      fprintf(stderr, "Bad regular expresion\n");
      exit(-1);
    }

    // get directory pointer to the current directory
    DIR * dir = opendir(".");
		if (dir == NULL) {
			return;
		}

    // find the matching filenames and then sort
    struct dirent * ent;
    regmatch_t match;

    maxEntries = 20;
    nEntries = 0;
    array = (char **) malloc (maxEntries * sizeof(char *));

    while ( (ent = readdir(dir)) != NULL) {
      if (regexec(&re, ent->d_name, 1, &match, 0) == 0) {
        if (nEntries == maxEntries) {
          // reallocate array size if necessary
          maxEntries *= 2;
          array = (char **) realloc(array, maxEntries * sizeof(char *));
          assert(array != NULL);
        }

        // exclude the invisible files
        if (ent->d_name[0] == '.') {
          if (arg[0] == '.') {
            array[nEntries] = strdup(ent->d_name);
            nEntries++;
          }
        } else {
          array[nEntries] = strdup(ent->d_name);
          nEntries++;
        }
      }
    }

    closedir(dir);
    regfree(&re);
		free(reg);

  } else {

    // with subdirectory
    maxEntries = 20;
    nEntries = 0;
    array = (char **) malloc (maxEntries * sizeof(char *));

    if (arg[0] == '/') {
      abs_path = true;
      expandWildcard(NULL, arg);
    } else if (arg[0] == '.' && arg[1] == '/') {
      abs_path = false;
      expandWildcard(NULL, arg + 2);
    } else {
      abs_path = false;
      expandWildcard(NULL, arg);
    }

  }

  // determine if the array has any valid wildcard matches
  if (array[0] == NULL) {
    Command::_currentSimpleCommand->insertArgument(strArg);
  } else {
    // sort the array by qsort() and add arguments to the command table
    qsort(array, nEntries, sizeof(char *), cmpfunc);
    for (int i = 0; i < nEntries; i++) {
      Command::_currentSimpleCommand->insertArgument(new std::string(array[i]));
    }
    delete strArg;
  }

  // free the array and close properly
  for (int i = 0; i < nEntries; i++) {
    free(array[i]);
  }
  free(array);
  
}



#if 0
main()
{
  yyparse();
}
#endif

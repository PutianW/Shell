/*
 * CS252: Shell project
 *
 * Template file.
 * You will need to add more code here to execute the command table.
 *
 * NOTE: You are responsible for fixing any bugs this code may have!
 *
 * DO NOT PUT THIS PROJECT IN A PUBLIC REPOSITORY LIKE GIT. IF YOU WANT 
 * TO MAKE IT PUBLICALLY AVAILABLE YOU NEED TO REMOVE ANY SKELETON CODE 
 * AND REWRITE YOUR PROJECT SO IT IMPLEMENTS FUNCTIONALITY DIFFERENT THAN
 * WHAT IS SPECIFIED IN THE HANDOUT. WE OFTEN REUSE PART OF THE PROJECTS FROM  
 * SEMESTER TO SEMESTER AND PUTTING YOUR CODE IN A PUBLIC REPOSITORY
 * MAY FACILITATE ACADEMIC DISHONESTY.
 */

#include <cstdio>
#include <cstdlib>
#include <unistd.h>
#include <iostream>
#include <fcntl.h>
#include <sys/wait.h>
#include <vector>
#include <cstring>
#include <stdio.h>

#include "command.hh"
#include "shell.hh"

extern void source(FILE *file);
std::string _last_arg;

std::string Command::getLastArg() {
	return _last_arg;
}

Command::Command() {
    // Initialize a new vector of Simple Commands
    _simpleCommands = std::vector<SimpleCommand *>();

    _outFile = NULL;
    _inFile = NULL;
    _errFile = NULL;
    _background = false;
    _append = false;
    _redirect_err = false;
    _last_return_code = -1;
    _last_PID = -1;
}

void Command::insertSimpleCommand( SimpleCommand * simpleCommand ) {
    // add the simple command to the vector
    _simpleCommands.push_back(simpleCommand);
}

void Command::clear() {
    // deallocate all the simple commands in the command vector
    for (auto simpleCommand : _simpleCommands) {
        delete simpleCommand;
    }

    // remove all references to the simple commands we've deallocated
    // (basically just sets the size to 0)
    _simpleCommands.clear();

    
    if ( _outFile ) {
        delete _outFile;
    }

    if ( _errFile && _errFile != _outFile ) {
        delete _errFile;
    }

    if ( _inFile ) {
        delete _inFile;
    }

    _outFile = NULL;
    _errFile = NULL;
    _inFile = NULL;
    _background = false;
    _append = false;
    _redirect_err = false;
}

void Command::print() {
    printf("\n\n");
    printf("              COMMAND TABLE                \n");
    printf("\n");
    printf("  #   Simple Commands\n");
    printf("  --- ----------------------------------------------------------\n");

    int i = 0;
    // iterate over the simple commands and print them nicely
    for ( auto & simpleCommand : _simpleCommands ) {
        printf("  %-3d ", i++ );
        simpleCommand->print();
    }

    printf( "\n\n" );
    printf( "  Output       Input        Error        Background\n" );
    printf( "  ------------ ------------ ------------ ------------\n" );
    printf( "  %-12s %-12s %-12s %-12s\n",
            _outFile?_outFile->c_str():"default",
            _inFile?_inFile->c_str():"default",
            _errFile?_errFile->c_str():"default",
            _background?"YES":"NO");
    printf( "\n\n" );
}

void Command::execute() {

    // multiple redirect error detect
    if ( _redirect_err ) {
        // Clear to prepare for next command
        clear();

        // Print new prompt
        if (isatty(0)) {
            Shell::prompt();
        }
        return;
    }

    // Don't do anything if there are no simple commands
    if ( _simpleCommands.size() == 0 && isatty(0)) {
        Shell::prompt();
        return;
    }

    // store the index of default standard in/out 
    int tempin = dup(0);
    int tempout = dup(1);
    int temperr = dup(2);

    // initialize error file
    int fderr;
    if ( _errFile ) {
        if ( _append) {
            fderr = open((_errFile)->c_str(), O_WRONLY | O_APPEND, 0777);
            dup2(fderr, 2);
            close(fderr);
        } else {
            fderr = open((_errFile)->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0777);
            dup2(fderr, 2);
            close(fderr);
        }
    }

    // initialize input index
    int fdin;

    if ( _inFile ) {
        // use the input file if it exists
        fdin = open((_inFile)->c_str(), O_RDONLY, 0777);
    } else {
        // use standard in if input file doesn't exist
        fdin = dup(tempin);
    }

    int ret;
    int fdout;

    for (int i = 0; i < (int) _simpleCommands.size(); i++) {
        // redirect the default input of the current command to fdin
        dup2(fdin, 0);
        close(fdin);

        if (i == (int) _simpleCommands.size() - 1) {
            // last command
            if ( _outFile ) {
                // redirect to outfile if it exists
                if ( _append ) {
                    fdout = open((_outFile)->c_str(), O_WRONLY | O_APPEND, 0777);
                } else {
                    fdout = open((_outFile)->c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0777);
                }
            } else {
                // redirect to standard out if outfile doesn't exist
                fdout = dup(tempout);
            }
        } else {
            // when it is not the last command
            // create pipe
            int fdpipe[2];
            pipe(fdpipe);
            // redirect pipe output
            fdout = fdpipe[1];
            // redirect input (which is the current pipe output) for the next command
            fdin = fdpipe[0];
        }

        // redirect the default output of current command to fdout
        // which can be _outfile/terminal/pipe_output 
        dup2(fdout, 1);
        close(fdout);

        // get the last argument
        _last_arg = *(_simpleCommands[i]->_arguments[_simpleCommands[i]->_arguments.size() - 1]);

        // create global environment variable
        extern char ** environ;

        // build-in function: setenv
        if (!strcmp(_simpleCommands[i]->_arguments[0]->c_str(), "setenv")) {
            if (setenv(_simpleCommands[i]->_arguments[1]->c_str(), _simpleCommands[i]->_arguments[2]->c_str(), 1)) {
                // error handler
                perror("setenv");
            }
            // return before any child process is created
	        clear();
	        if (isatty(0)) {
                Shell::prompt();
	        }

	        dup2(tempin, 0);
            dup2(tempout, 1);
            dup2(temperr, 2);
            close(tempin);
            close(tempout);
            close(temperr);
            clear();

            return;
        }

        // build-in function: unsetenv
        if (!strcmp(_simpleCommands[i]->_arguments[0]->c_str(), "unsetenv")) {
            if (unsetenv(_simpleCommands[i]->_arguments[1]->c_str())) {
                // error handler
                perror("unsetenv");
            }
            // return before any child process is created
	        clear();
	        if (isatty(0)) {
                Shell::prompt();
	        }

	        dup2(tempin, 0);
            dup2(tempout, 1);
            dup2(temperr, 2);
            close(tempin);
            close(tempout);
            close(temperr);
            clear();

            return;
        }

        // build-in function: source
        if (!strcmp(_simpleCommands[i]->_arguments[0]->c_str(), "source")) {

            if (_simpleCommands[i]->_arguments.size() != 2) {
                fprintf(stderr, "source: invalid input argument\n");
                return;
            }
            FILE * file = fopen(_simpleCommands[i]->_arguments[1]->c_str(), "r");
            if (!file) {
                perror("source");
            } else {
                _simpleCommands.clear();
                source(file);
                fclose(file);
            }

	        dup2(tempin, 0);
            dup2(tempout, 1);
            dup2(temperr, 2);
            close(tempin);
            close(tempout);
            close(temperr);
            clear();

            return;
        }

        // build-in function: cd
        if (!strcmp(_simpleCommands[i]->_arguments[0]->c_str(), "cd")) {

            if (_simpleCommands[i]->_arguments.size() == 1) {
                // 0 argument
                if (chdir(getenv("HOME")) != 0) {
                    perror("cd");
                }
            } else if (_simpleCommands[i]->_arguments.size() == 2) {
                // 1 argument
                if (chdir(_simpleCommands[i]->_arguments[1]->c_str()) != 0) {
                    fprintf(stderr, "cd: can't cd to %s\n", _simpleCommands[i]->_arguments[1]->c_str());
                }
            } else {
                // more than 1 argument
                fprintf(stderr, "cd: too many arguments\n");
            }

            // return before any child process is created
	        dup2(tempin, 0);
            dup2(tempout, 1);
            dup2(temperr, 2);
            close(tempin);
            close(tempout);
            close(temperr);
            clear();

	        if (isatty(0)) {
                Shell::prompt();
	        }

            return;
        }

        // create child process to execute the current command
        ret = fork();
        if (ret == 0) {

            // buildin function: printenv
            if ( !strcmp(_simpleCommands[i]->_arguments[0]->c_str(), "printenv") ) {
                char **p = environ;
                while (*p != NULL) {
                    printf("%s\n", *p);
                    p++;
                }
                exit(0);
            }

            // create an array of char* (string) pointers with size of the number of arguments + 1
            const char** cmd_and_arguments = new const char*[_simpleCommands[i]->_arguments.size() + 1];

            for (int t = 0; t < (int) _simpleCommands[i]->_arguments.size(); t++) {
                // convert each c++ string argument into char* argument
                cmd_and_arguments[t] = _simpleCommands[i]->_arguments[t]->c_str();
            }

            // set the last argument to NULL
            cmd_and_arguments[_simpleCommands[i]->_arguments.size()] = nullptr;

            // execute the command
            execvp(cmd_and_arguments[0], (char * const *) cmd_and_arguments);
            
            // deallocate the list
            for (int z = 0; z < (int) _simpleCommands[i]->_arguments.size() + 1; z++) {
                delete[] cmd_and_arguments[z];
            }
            delete[] cmd_and_arguments;

            perror("execvp");
            exit(1);
        }
    }

    // restore the in/out to default standard in/out
    dup2(tempin, 0);
    dup2(tempout, 1);
    dup2(temperr, 2);
    close(tempin);
    close(tempout);
    close(temperr);

    if (!_background) {
        int status;
        // parent process wait for last command to finish
        waitpid(ret, &status, 0);
        _last_return_code = WEXITSTATUS(status);
    } else {
        _last_PID = ret;
    }

    // Clear to prepare for next command
    clear();

    // Print new prompt
    if (isatty(0)) {        
        Shell::prompt();
    }

}

SimpleCommand * Command::_currentSimpleCommand;

#ifndef ANSOMNIA_TEST_HOME_H
#define ANSOMNIA_TEST_HOME_H

/// Name of the environment variable the loader sets ("ANSOMNIA_HOME").
const char *ansomnia_test_home_key(void);

/// The throwaway directory ANSOMNIA_HOME was pointed at when the test bundle
/// loaded, or NULL if the loader has not run.
const char *ansomnia_test_home_root(void);

#endif

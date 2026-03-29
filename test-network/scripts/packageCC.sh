#!/usr/bin/env bash

source scripts/utils.sh

CC_NAME=${1}
CC_SRC_PATH=${2}
CC_SRC_LANGUAGE=${3}
CC_VERSION=${4}
CC_PACKAGE_ONLY=${5:-false}

println "executing with the following"
println "- CC_NAME: ${C_GREEN}${CC_NAME}${C_RESET}"
println "- CC_SRC_PATH: ${C_GREEN}${CC_SRC_PATH}${C_RESET}"
println "- CC_SRC_LANGUAGE: ${C_GREEN}${CC_SRC_LANGUAGE}${C_RESET}"
println "- CC_VERSION: ${C_GREEN}${CC_VERSION}${C_RESET}"

FABRIC_CFG_PATH=$PWD/../config/

#User has not provided a name
if [ -z "$CC_NAME" ] || [ "$CC_NAME" = "NA" ]; then
  fatalln "No chaincode name was provided. Valid call example: ./network.sh packageCC -ccn basic -ccp chaincode/asset-transfer-basic/chaincode-go -ccv 1.0 -ccl go"

# User has not provided a path
elif [ -z "$CC_SRC_PATH" ] || [ "$CC_SRC_PATH" = "NA" ]; then
  fatalln "No chaincode path was provided. Valid call example: ./network.sh packageCC -ccn basic -ccp chaincode/asset-transfer-basic/chaincode-go -ccv 1.0 -ccl go"

# User has not provided a language
elif [ -z "$CC_SRC_LANGUAGE" ] || [ "$CC_SRC_LANGUAGE" = "NA" ]; then
  fatalln "No chaincode language was provided. Valid call example: ./network.sh packageCC -ccn basic -ccp chaincode/asset-transfer-basic/chaincode-go -ccv 1.0 -ccl go"

## Make sure that the path to the chaincode exists
elif [ ! -d "$CC_SRC_PATH" ]; then
  fatalln "Path to chaincode does not exist. Please provide different path."
fi

CC_SRC_LANGUAGE=$(echo "$CC_SRC_LANGUAGE" | tr [:upper:] [:lower:])

# do some language specific preparation to the chaincode before packaging
if [ "$CC_SRC_LANGUAGE" = "go" ]; then
  CC_RUNTIME_LANGUAGE=golang

  infoln "Vendoring Go dependencies at $CC_SRC_PATH"
  pushd $CC_SRC_PATH
  GO111MODULE=on go mod vendor
  popd
  successln "Finished vendoring Go dependencies"

elif [ "$CC_SRC_LANGUAGE" = "java" ]; then
  CC_RUNTIME_LANGUAGE=java

  infoln "Compiling Java code..."
  pushd $CC_SRC_PATH
  ./gradlew installDist
  popd
  successln "Finished compiling Java code"
  CC_SRC_PATH=$CC_SRC_PATH/build/install/$CC_NAME

elif [ "$CC_SRC_LANGUAGE" = "javascript" ]; then
  CC_RUNTIME_LANGUAGE=node

elif [ "$CC_SRC_LANGUAGE" = "typescript" ]; then
  CC_RUNTIME_LANGUAGE=node

  infoln "Compiling TypeScript code into JavaScript..."
  pushd $CC_SRC_PATH
  npm install
  npm run build
  popd
  successln "Finished compiling TypeScript code into JavaScript"

else
  fatalln "The chaincode language ${CC_SRC_LANGUAGE} is not supported by this script. Supported chaincode languages are: go, java, javascript, and typescript"
  exit 1
fi

verifyResult() {
  if [ $1 -ne 0 ]; then
    fatalln "$2"
  fi
}

packageChaincode() {
  # Log diagnostic information
  infoln "📋 Packaging Diagnostic Information:"
  infoln "  Current directory: $(pwd)"
  infoln "  Chaincode name: ${CC_NAME}"
  infoln "  Chaincode source path: ${CC_SRC_PATH}"
  infoln "  Chaincode language: ${CC_SRC_LANGUAGE} (runtime: ${CC_RUNTIME_LANGUAGE})"
  infoln "  Version: ${CC_VERSION}"
  
  # Verify source path exists
  if [ ! -d "${CC_SRC_PATH}" ]; then
    fatalln "❌ Chaincode source path does not exist: ${CC_SRC_PATH}"
  fi
  infoln "  ✓ Source path exists"
  
  # For Go chaincode, verify go.mod exists
  if [ "${CC_RUNTIME_LANGUAGE}" = "golang" ]; then
    if [ ! -f "${CC_SRC_PATH}/go.mod" ]; then
      fatalln "❌ go.mod not found in ${CC_SRC_PATH}/go.mod"
    fi
    infoln "  ✓ go.mod found"
    
    # List Go files
    infoln "  Go files in source:"
    ls -1 ${CC_SRC_PATH}/*.go | sed 's/^/    /'
  fi
  
  # Clean up old package files
  rm -f ${CC_NAME}.tar.gz log.txt
  infoln "  ✓ Cleaned up old package files"
  
  set -x
  if [ ${CC_PACKAGE_ONLY} = true ] ; then
    mkdir -p packagedChaincode
    peer lifecycle chaincode package packagedChaincode/${CC_NAME}_${CC_VERSION}.tar.gz --path ${CC_SRC_PATH} --lang ${CC_RUNTIME_LANGUAGE} --label ${CC_NAME}_${CC_VERSION} >&log.txt
  else
    peer lifecycle chaincode package ${CC_NAME}.tar.gz --path ${CC_SRC_PATH} --lang ${CC_RUNTIME_LANGUAGE} --label ${CC_NAME}_${CC_VERSION} >&log.txt
  fi
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  
  # Verify package file was created
  if [ ${CC_PACKAGE_ONLY} = true ]; then
    if [ ! -f "packagedChaincode/${CC_NAME}_${CC_VERSION}.tar.gz" ]; then
      fatalln "❌ Package file was not created: packagedChaincode/${CC_NAME}_${CC_VERSION}.tar.gz"
    fi
    infoln "  ✓ Package created: packagedChaincode/${CC_NAME}_${CC_VERSION}.tar.gz"
    PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid packagedChaincode/${CC_NAME}_${CC_VERSION}.tar.gz)
  else
    if [ ! -f "${CC_NAME}.tar.gz" ]; then
      fatalln "❌ Package file was not created: ${CC_NAME}.tar.gz"
    fi
    infoln "  ✓ Package created: ${CC_NAME}.tar.gz"
    PACKAGE_ID=$(peer lifecycle chaincode calculatepackageid ${CC_NAME}.tar.gz)
  fi
  
  verifyResult $res "Chaincode packaging has failed"
  successln "✅ Chaincode is packaged (ID: ${PACKAGE_ID})"
}

## package the chaincode
packageChaincode

exit 0

const fs = require("fs");
const path = require("path");

// Function to convert a JSON contract file to a TypeScript ABI file
function generateAbiFile(inputPath, outputFileName) {
  console.log(`Processing ${inputPath}...`);

  // Read and parse the JSON file
  let jsonData;
  try {
    const rawData = fs.readFileSync(inputPath, "utf8");
    jsonData = JSON.parse(rawData);
  } catch (err) {
    console.error(`Error reading or parsing ${inputPath}:`, err);
    return false;
  }

  // Ensure that the JSON contains an 'abi' property
  if (!jsonData.abi) {
    console.error(`The JSON file does not contain an "abi" property.`);
    return false;
  }

  // Format the ABI using JSON.stringify with 2-space indentation
  let formattedAbi = JSON.stringify(jsonData.abi, null, 2);

  // Remove quotes around keys (for keys that are valid identifiers)
  formattedAbi = formattedAbi.replace(/"([a-zA-Z_][a-zA-Z0-9_]*)":/g, "$1:");

  // Build the TypeScript export content with "as const" appended
  const exportName = outputFileName.replace(".ts", "");
  const tsContent = `export const ${exportName} = ${formattedAbi} as const;\n`;

  // Write the output TS file to the abis directory
  const outputPath = path.resolve(__dirname, "../", "abis", outputFileName);

  // Ensure abis directory exists
  const abisDir = path.dirname(outputPath);
  if (!fs.existsSync(abisDir)) {
    fs.mkdirSync(abisDir, { recursive: true });
  }

  try {
    fs.writeFileSync(outputPath, tsContent, "utf8");
    console.log(`Successfully written ${outputPath}`);
    return true;
  } catch (err) {
    console.error(`Error writing to ${outputPath}:`, err);
    return false;
  }
}

// Generate TypeScript ABI for TokenFactory
const tokenFactoryInputPath = path.resolve(
  __dirname,
  "../out/TokenFactory.sol/TokenFactory.json"
);
generateAbiFile(tokenFactoryInputPath, "TokenFactoryAbi.ts");

// Generate TypeScript ABI for PoolManager (from v4-core)
const poolManagerInputPath = path.resolve(
  __dirname,
  "../lib/hookmate/src/artifacts/V4PoolManager.sol"
);

// Check if V4PoolManager.sol is a JSON file or needs a different approach
if (fs.existsSync(poolManagerInputPath)) {
  // Read the file to understand its format
  try {
    const content = fs.readFileSync(poolManagerInputPath, "utf8");
    if (content.startsWith("{")) {
      // It's a JSON file
      generateAbiFile(poolManagerInputPath, "PoolManagerAbi.ts");
    } else {
      console.log(
        "V4PoolManager.sol appears to be a Solidity file, not a JSON artifact."
      );
      console.log("Looking for alternative PoolManager artifacts...");

      // Try to find PoolManager JSON in v4-core out directory
      const v4CoreOutPath = path.resolve(
        __dirname,
        "../lib/uniswap-hooks/lib/v4-core/out/PoolManager.sol/PoolManager.json"
      );

      if (fs.existsSync(v4CoreOutPath)) {
        generateAbiFile(v4CoreOutPath, "PoolManagerAbi.ts");
      } else {
        console.error(
          "Could not find PoolManager.json artifact. You may need to compile the v4-core contracts first."
        );
        console.log(
          "Try running: cd lib/uniswap-hooks/lib/v4-core && forge build"
        );
      }
    }
  } catch (err) {
    console.error("Error reading V4PoolManager file:", err);
  }
} else {
  console.error(`PoolManager artifact not found at ${poolManagerInputPath}`);
  console.log("Looking for alternative paths...");

  // Alternative paths to check
  const alternativePaths = [
    "../lib/uniswap-hooks/lib/v4-core/out/PoolManager.sol/PoolManager.json",
    "../out/PoolManager.sol/PoolManager.json",
    "../lib/hookmate/src/artifacts/V4PoolManagerDeployer.sol",
  ];

  for (const altPath of alternativePaths) {
    const fullPath = path.resolve(__dirname, altPath);
    if (fs.existsSync(fullPath)) {
      console.log(`Found PoolManager artifact at: ${fullPath}`);
      generateAbiFile(fullPath, "PoolManagerAbi.ts");
      break;
    }
  }
}

console.log("\n=== ABI Generation Complete ===");
console.log("Generated files should be available in:");
console.log(`- ${path.resolve(__dirname, "../abis/TokenFactoryAbi.ts")}`);
console.log(`- ${path.resolve(__dirname, "../abis/PoolManagerAbi.ts")}`);
console.log("\nYou can now import these ABIs in your frontend/backend:");
console.log("import { TokenFactoryAbi } from './abis/TokenFactoryAbi';");
console.log("import { PoolManagerAbi } from './abis/PoolManagerAbi';");

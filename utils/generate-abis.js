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

console.log("=== Generating ABIs for AgentFi Contracts ===\n");

// Generate TypeScript ABI for BondingCurve
const bondingCurveInputPath = path.resolve(
  __dirname,
  "../out/BondingCurve.sol/BondingCurve.json"
);
generateAbiFile(bondingCurveInputPath, "BondingCurveAbi.ts");

// Generate TypeScript ABI for TokenFactory
const tokenFactoryInputPath = path.resolve(
  __dirname,
  "../out/TokenFactory.sol/TokenFactory.json"
);
generateAbiFile(tokenFactoryInputPath, "TokenFactoryAbi.ts");

// Generate TypeScript ABI for MockERC20
const mockERC20InputPath = path.resolve(
  __dirname,
  "../out/MockERC20.sol/MockERC20.json"
);
generateAbiFile(mockERC20InputPath, "MockERC20Abi.ts");

console.log("\n=== ABI Generation Complete ===");
console.log("Generated files should be available in:");
console.log(`- ${path.resolve(__dirname, "../abis/BondingCurveAbi.ts")}`);
console.log(`- ${path.resolve(__dirname, "../abis/TokenFactoryAbi.ts")}`);
console.log(`- ${path.resolve(__dirname, "../abis/MockERC20Abi.ts")}`);
console.log("\nYou can now import these ABIs in your frontend/backend:");
console.log("import { BondingCurveAbi } from './abis/BondingCurveAbi';");
console.log("import { TokenFactoryAbi } from './abis/TokenFactoryAbi';");
console.log("import { MockERC20Abi } from './abis/MockERC20Abi';");
console.log(
  "\nNote: Make sure to run 'forge build' first to generate the JSON artifacts!"
);

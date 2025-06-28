import ArgumentParser
import FluxSwift
import Foundation
import Hub
import MLX
import MLXNN
import MLXRandom
import Progress
import Tokenizers

let defaultTokenLocation = NSString("~/.cache/huggingface/token").expandingTildeInPath

@main
struct FluxTool: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "flux",
    abstract: "FLUX image generation tool",
    discussion: "Generate images using the FLUX model"
  )

  @Option(name: .long, help: "The prompt to generate an image from")
  var prompt: String = "A cat is sitting on a tree"

  @Option(name: .long, help: "Image width")
  var width: Int = 512

  @Option(name: .long, help: "Image height")
  var height: Int = 512

  @Option(name: .long, help: "Number of inference steps")
  var steps: Int = 4

  @Option(name: .long, help: "Guidance scale")
  var guidance: Float = 3.5

  @Option(name: .long, help: "Output image path")
  var output: String = "output_image.png"

  @Option(name: .long, help: "FLUX model repository")
  var repo: String = "black-forest-labs/FLUX.1-schnell"

  @Option(name: .long, help: "Random seed for generation (default: 2)")
  var seed: UInt64?

  @Flag(name: [.long, .short], help: "Enable quantization")
  var quantize: Bool = false

  @Flag(inversion: .prefixedNo, help: "Enable float16 precision (default: true)")
  var float16: Bool = true

  @Option(name: .long, help: "FLUX model type (schnell or dev)")
  var model: String = "schnell"

  @Option(name: .long, help: "Hugging Face API token (required for dev model)")
  var hfToken: String?

  @Option(name: .long, help: "Path to local LoRA weights file or Hugging Face repo id")
  var loraPath: String?

  @Option(name: .long, help: "Path to initial image for image-to-image generation (Kontext model only)")
  var initImagePath: String?

  func run() async throws {
    var progressBar: ProgressBar?
    var token: String?
    let selectedModel: FluxConfiguration
    switch model.lowercased() {
    case "schnell":
      selectedModel = FluxConfiguration.flux1Schnell
    case "dev":
      selectedModel = FluxConfiguration.flux1Dev
      token = hfToken

      if token == nil {
        token = try? String(contentsOfFile: defaultTokenLocation, encoding: .utf8)
        print(
          "Hugging Face token is not provided. Using default token from \(defaultTokenLocation)")
      }
    case "kontext":
      selectedModel = FluxConfiguration.flux1KontextDev
      token = hfToken

      if token == nil {
        token = try? String(contentsOfFile: defaultTokenLocation, encoding: .utf8)
        print(
          "Hugging Face token is not provided. Using default token from \(defaultTokenLocation)")
      }
    default:
      throw ValidationError("Invalid model type. Please choose 'schnell', 'dev' or 'kontext'.")
    }
    
    // Validate image-to-image is only used with kontext
    if initImagePath != nil && model.lowercased() != "kontext" {
      throw ValidationError("Image-to-image generation is only supported with the 'kontext' model. Use --model kontext")
    }

    try await selectedModel.download(hub: (model == "dev" || model == "kontext") ? HubApi(hfToken: token) : HubApi()) {
      progress in
      if progressBar == nil {
        let complete = progress.fractionCompleted
        if complete < 0.99 {
          progressBar = ProgressBar(count: 1000)
          if complete > 0 {
            print("Resuming download (\(Int(complete * 100))% complete)")
          } else {
            print("Downloading flux.1 \(model) model...")
          }
          print()
        }
      }

      let complete = Int(progress.fractionCompleted * 1000)
      progressBar?.setValue(complete)
    }

    let loadConfiguration = LoadConfiguration(
      float16: float16,
      quantize: quantize,
      loraPath: loraPath
    )

    if let loraPath = loadConfiguration.loraPath {
      if !FileManager.default.fileExists(atPath: loraPath) {
        try await selectedModel.downloadLoraWeights(loadConfiguration: loadConfiguration) {
          progress in
          if progressBar == nil {
            let complete = progress.fractionCompleted
            if complete < 0.99 {
              progressBar = ProgressBar(count: 1000)
              if complete > 0 {
                print("Resuming download (\(Int(complete * 100))% complete)")
              } else {
                print("Downloading lora weights for \(loraPath) model...")
              }
              print()
            }
          }

          let complete = Int(progress.fractionCompleted * 1000)
          progressBar?.setValue(complete)
        }
      }
    }

    let generator: ImageGenerator?
    var denoiser: Any?

    let parameters: EvaluateParameters = EvaluateParameters(
      width: width, height: height, numInferenceSteps: steps, guidance: guidance, seed: seed,
      prompt: prompt, shiftSigmas: (model.lowercased() == "dev" || model.lowercased() == "kontext") ? true : false)

    if let initImagePath = initImagePath {
      guard let kontextGenerator = try selectedModel.kontextImageToImageGenerator(hub: (model == "kontext") ? HubApi(hfToken: token) : HubApi(), configuration: loadConfiguration) else {
        throw ValidationError("Failed to initialize Kontext image-to-image generator")
      }
      
      generator = kontextGenerator
      generator?.ensureLoaded()

      let image = try Image(url: URL(fileURLWithPath: initImagePath))
      
      let normalized = (image.data.asType(.float32) / 255) * 2 - 1
      

      let input = normalized

      denoiser = kontextGenerator.generateKontextLatents(
        image: input,
        parameters: parameters
      )
    } else {
      generator = try selectedModel.textToImageGenerator(hub: (model == "dev" || model == "kontext") ? HubApi(hfToken: token) : HubApi(), configuration: loadConfiguration)
      generator?.ensureLoaded()
      denoiser = (generator as? TextToImageGenerator)?.generateLatents(parameters: parameters)
    }

    print("Starting image generation with parameters:")
    print("- Prompt: \(prompt)")
    print("- Dimensions: \(width)x\(height)")
    print("- Steps: \(steps)")
    print("- Guidance: \(guidance)")
    print("- Model: \(model)")
    if let seed {
      print("- Seed: \(seed)")
    }
    print("- Float16: \(float16)")
    print("- Quantize: \(quantize)")
    if let loraPath = loraPath {
      print("- LoRA: \(loraPath)")
    }
    print("- Output: \(output)")
    if let initImagePath {
      print("- Init Image: \(initImagePath)")
      if model.lowercased() == "kontext" {
        print("- Mode: Kontext Image-to-Image")
      }
    }

    var lastXt: MLXArray!
    if let kontextDenoiser = denoiser as? KontextDenoiseIterator {
      var iterator = kontextDenoiser
      while let xt = iterator.next() {
        print("Step \(iterator.i)/\(parameters.numInferenceSteps)")
        eval(xt)
        lastXt = xt
      }
    } else if let standardDenoiser = denoiser as? DenoiseIterator {
      var iterator = standardDenoiser
      while let xt = iterator.next() {
        print("Step \(iterator.i)/\(parameters.numInferenceSteps)")
        eval(xt)
        lastXt = xt
      }
    }

    print("Latent generation complete. Unpacking latents...")
    let unpackedLatents = unpackLatents(lastXt, height: parameters.height, width: parameters.width)

    print("Decoding image...")
    let decoded = generator?.decode(xt: unpackedLatents)
    let imageData = decoded?.squeezed()

    print("Processing final image data...")
    let raster = (imageData! * 255).asType(.uint8)
    let image = Image(raster)

    print("Saving image...")
    var outputURL = URL(fileURLWithPath: output)
    var counter = 1
    let originalFilename = outputURL.deletingPathExtension().lastPathComponent
    let fileExtension = outputURL.pathExtension

    while FileManager.default.fileExists(atPath: outputURL.path) {
      let newFilename: String
      if originalFilename.contains("_")
        && originalFilename.split(separator: "_").last?.allSatisfy({ $0.isNumber }) == true
      {
        // If the filename already ends with _number, increment that number
        let parts = originalFilename.split(separator: "_")
        let baseFilename = parts.dropLast().joined(separator: "_")
        newFilename = "\(baseFilename)_\(counter)"
      } else {
        newFilename = "\(originalFilename)_\(counter)"
      }
      outputURL = outputURL.deletingLastPathComponent().appendingPathComponent(newFilename)
        .appendingPathExtension(fileExtension)
      counter += 1
    }

    do {
      try image.save(url: outputURL)
      print("Image saved successfully at: \(outputURL.path)")
    } catch {
      print("Error saving image: \(error)")
    }
  }

  func unpackLatents(_ latents: MLXArray, height: Int, width: Int) -> MLXArray {
    let reshaped = latents.reshaped(1, height / 16, width / 16, 16, 2, 2)
    let transposed = reshaped.transposed(0, 1, 4, 2, 5, 3)
    return transposed.reshaped(1, height / 16 * 2, width / 16 * 2, 16)
  }
}

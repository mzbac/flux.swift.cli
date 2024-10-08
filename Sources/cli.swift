import ArgumentParser
import Foundation
import MLX
import Hub
import MLXNN
import MLXRandom
import Tokenizers
import FluxSwift
import Progress

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
    var seed: UInt64 = 2
    
    @Flag(name: [.long, .short], help: "Enable quantization")
    var quantize: Bool = false
    
    @Flag(inversion: .prefixedNo, help: "Enable float16 precision (default: true)")
    var float16: Bool = true
    
    func run() async throws {
        var progressBar: ProgressBar?

        try await FluxConfiguration.flux1Schnell.download { progress in
            if progressBar == nil {
                let complete = progress.fractionCompleted
                if complete < 0.99 {
                    progressBar = ProgressBar(count: 1000)
                    if complete > 0 {
                        print("Resuming download (\(Int(complete * 100))% complete)")
                    } else {
                        print("Downloading")
                    }
                    print()
                }
            }

            let complete = Int(progress.fractionCompleted * 1000)
            progressBar?.setValue(complete)
        }
        
        let loadConfiguration = LoadConfiguration(float16: float16, quantize: quantize)
        let generator = try FluxConfiguration.flux1Schnell.textToImageGenerator(
            configuration: loadConfiguration)
        generator?.ensureLoaded()
        var parameters = FluxConfiguration.flux1Schnell.defaultParameters()
        parameters.height = height
        parameters.width = width
        parameters.prompt = prompt
        parameters.numInferenceSteps = steps
        print("Starting image generation with parameters:")
        print("- Prompt: \(prompt)")
        print("- Dimensions: \(width)x\(height)")
        print("- Steps: \(steps)")
        print("- Guidance: \(guidance)")
        
        var denoiser = generator?.generateLatents(parameters: parameters)
        var lastXt: MLXArray!
        while let xt = denoiser!.next() {
            print("Step \(denoiser!.i)/\(parameters.numInferenceSteps)")
            eval(xt)
            lastXt = xt
        }

        print("Latent generation complete. Unpacking latents...")
        let unpackedLatents = unpackLatents(lastXt, height: parameters.height, width: parameters.width)
        
        print("Decoding image...")
        let decoded = generator?.decode(xt: unpackedLatents)
        var imageData = decoded?.squeezed()
        imageData = imageData!.transposed(1, 2, 0)
        
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
            if originalFilename.contains("_") && originalFilename.split(separator: "_").last?.allSatisfy({ $0.isNumber }) == true {
                // If the filename already ends with _number, increment that number
                let parts = originalFilename.split(separator: "_")
                let baseFilename = parts.dropLast().joined(separator: "_")
                newFilename = "\(baseFilename)_\(counter)"
            } else {
                newFilename = "\(originalFilename)_\(counter)"
            }
            outputURL = outputURL.deletingLastPathComponent().appendingPathComponent(newFilename).appendingPathExtension(fileExtension)
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
        let transposed = reshaped.transposed(0, 3, 1, 4, 2, 5)
        return transposed.reshaped(1, 16, height / 16 * 2, width / 16 * 2)
    }
}

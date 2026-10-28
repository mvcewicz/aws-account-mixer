import Foundation

/// Places in the console you can go to right after signing in.
nonisolated enum ConsoleService: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, ec2, ecs, lambda, s3, cloudWatch, rds, dynamoDB, cloudFormation, route53, cloudFront, iam, billing

    var id: Self { self }

    var title: String {
        switch self {
        case .home: String(localized: "Console home")
        case .ec2: "EC2"
        case .ecs: "ECS"
        case .lambda: "Lambda"
        case .s3: "S3"
        case .cloudWatch: "CloudWatch"
        case .rds: "RDS"
        case .dynamoDB: "DynamoDB"
        case .cloudFormation: "CloudFormation"
        case .route53: "Route 53"
        case .cloudFront: "CloudFront"
        case .iam: "IAM"
        case .billing: String(localized: "Billing")
        }
    }

    private var path: String {
        switch self {
        case .home: "console/home"
        case .ec2: "ec2/home"
        case .ecs: "ecs/v2/home"
        case .lambda: "lambda/home"
        case .s3: "s3/home"
        case .cloudWatch: "cloudwatch/home"
        case .rds: "rds/home"
        case .dynamoDB: "dynamodbv2/home"
        case .cloudFormation: "cloudformation/home"
        case .route53: "route53/v2/home"
        case .cloudFront: "cloudfront/v4/home"
        case .iam: "iam/home"
        case .billing: "billing/home"
        }
    }

    func url(region: String) -> URL {
        var components = URLComponents(string: "https://console.aws.amazon.com/\(path)")!
        if !region.isEmpty {
            components.queryItems = [URLQueryItem(name: "region", value: region)]
        }
        return components.url!
    }
}

nonisolated struct AWSRegion: Identifiable, Sendable {
    var code: String
    var name: String
    var id: String { code }
    var label: String { "\(name) (\(code))" }

    static let all: [AWSRegion] = [
        AWSRegion(code: "eu-central-1", name: "Frankfurt"),
        AWSRegion(code: "eu-central-2", name: "Zurich"),
        AWSRegion(code: "eu-west-1", name: "Ireland"),
        AWSRegion(code: "eu-west-2", name: "London"),
        AWSRegion(code: "eu-west-3", name: "Paris"),
        AWSRegion(code: "eu-north-1", name: "Stockholm"),
        AWSRegion(code: "eu-south-1", name: "Milan"),
        AWSRegion(code: "us-east-1", name: "N. Virginia"),
        AWSRegion(code: "us-east-2", name: "Ohio"),
        AWSRegion(code: "us-west-1", name: "N. California"),
        AWSRegion(code: "us-west-2", name: "Oregon"),
        AWSRegion(code: "ca-central-1", name: "Canada"),
        AWSRegion(code: "sa-east-1", name: "São Paulo"),
        AWSRegion(code: "ap-south-1", name: "Mumbai"),
        AWSRegion(code: "ap-northeast-1", name: "Tokyo"),
        AWSRegion(code: "ap-northeast-2", name: "Seoul"),
        AWSRegion(code: "ap-southeast-1", name: "Singapore"),
        AWSRegion(code: "ap-southeast-2", name: "Sydney"),
        AWSRegion(code: "me-central-1", name: "UAE"),
        AWSRegion(code: "af-south-1", name: "Cape Town"),
    ]
}

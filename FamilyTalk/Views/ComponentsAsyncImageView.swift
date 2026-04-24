//
//  AsyncImageView.swift
//  FamilyTalk
//
//  Created by Dmitrii Gramoteev on 23.04.2026.
//

import SwiftUI

struct AsyncImageView: View {
    let url: String?
    let placeholder: String
    
    var body: some View {
        if let urlString = url, let imageURL = URL(string: urlString) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }
    
    private var placeholderView: some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .overlay {
                Text(placeholder)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
    }
}

#Preview {
    AsyncImageView(url: nil, placeholder: "JD")
        .frame(width: 50, height: 50)
}

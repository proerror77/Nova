//
//  CustomView346.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView346: View {
    @State public var image227Path: String = "image227_41083"
    @State public var text192Text: String = "Bruce Li"
    var body: some View {
        VStack(alignment: .center, spacing: 13) {
            Image(image227Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 172, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(86)
            Text(text192Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 19))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 172, height: 205, alignment: .center)
    }
}

struct CustomView346_Previews: PreviewProvider {
    static var previews: some View {
        CustomView346()
    }
}

//
//  CustomView264.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView264: View {
    @State public var text147Text: String = "Following"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text147Text)
                            .foregroundColor(Color(red: 0.51, green: 0.51, blue: 0.51, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 18))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
        }
        .frame(width: 81, height: 20, alignment: .topLeading)
    }
}

struct CustomView264_Previews: PreviewProvider {
    static var previews: some View {
        CustomView264()
    }
}
